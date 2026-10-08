import json
import logging
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi.responses import HTMLResponse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.constants import EMERGENCY_SERVICE_CATEGORIES, find_service_job, format_price_label
from app.config import settings
from app.payments import (
    PaymentGatewayError,
    decode_response,
    money,
    sign_fields,
    status_check,
    verify_response_signature,
)
from app.database import get_db
from app.deps import get_current_user
from app.routers.providers import EMERGENCY_LOCATION_MAX_AGE, provider_has_active_job
from app.notifications import (
    notify_booking_created,
    notify_cash_received,
    notify_payment_successful,
    notify_status_change,
)
from app.models import (
    Booking,
    BookingStatus,
    ProviderProfile,
    PaymentAttempt,
    Rating,
    User,
    UserRole,
    VerificationStatus,
)
from app.schemas import (
    BookingCreateRequest,
    EmergencyBookingCreateRequest,
    CustomerLocationUpdateRequest,
    BookingLocationUpdateRequest,
    BookingOut,
    BookingStatusUpdateRequest,
    ExtraChargeUpdateRequest,
    EsewaPaymentInitOut,
    EsewaVerifyRequest,
    RatingCreateRequest,
)

# Statuses during which a provider is expected to be actively navigating to
# the customer, and so is allowed to push live-location updates. Chosen to
# match exactly what the frontend's navigation map keeps rendering (see
# ProviderNavigationMap): it starts tracking on 'on_the_way' and only stops
# once the booking is marked 'completed', passing through 'arrived' in
# between without interruption.
_LOCATION_SHARING_STATUSES = (BookingStatus.accepted, BookingStatus.on_the_way, BookingStatus.arrived)

logger = logging.getLogger("uvicorn.error")

router = APIRouter(prefix="/api/bookings", tags=["bookings"])


def _to_booking_out(
    booking: Booking,
    customer_name: str,
    customer_phone: str | None,
    rating: Rating | None = None,
) -> BookingOut:
    # Provider identity is intentionally not part of the response: customers
    # book a service and never see which individual provider was assigned.
    return BookingOut(
        id=booking.id,
        customer_id=booking.customer_id,
        customer_name=customer_name,
        customer_phone=customer_phone,
        service_category=booking.service_category,
        job_title=booking.job_title,
        # Numeric comes back as a Decimal; the schema is float, so convert
        # here rather than relying on Pydantic to do it silently.
        price=float(booking.price) if booking.price is not None else None,
        price_type=booking.price_type,
        # Derived from the booking's *own* snapshotted price, not from the
        # current catalogue — a booking always shows the price it was made
        # at, even if that job has since been repriced.
        price_label=format_price_label(booking.price, booking.price_type),
        extra_charges=float(booking.extra_charges or 0),
        extra_charge_note=booking.extra_charge_note,
        total_amount=(float(Decimal(str(booking.price or 0)) + Decimal(str(booking.extra_charges or 0)))
                      if booking.price is not None else None),
        payment_status=booking.payment_status,
        payment_reference=booking.payment_reference,
        payment_method=booking.payment_method,
        address=booking.address,
        latitude=booking.latitude,
        longitude=booking.longitude,
        problem_description=booking.problem_description,
        notes=booking.notes,
        preferred_date=booking.preferred_date,
        status=booking.status,
        created_at=booking.created_at,
        updated_at=booking.updated_at,
        provider_latitude=booking.provider_latitude,
        provider_longitude=booking.provider_longitude,
        provider_location_updated_at=booking.provider_location_updated_at,
        customer_latitude=booking.customer_latitude,
        customer_longitude=booking.customer_longitude,
        customer_location_updated_at=booking.customer_location_updated_at,
        is_emergency=bool(booking.is_emergency),
        rating_stars=rating.stars if rating else None,
        rating_comment=rating.comment if rating else None,
        rated_at=rating.created_at if rating else None,
    )


# A booking counts towards a provider's current workload until it reaches
# one of the terminal statuses (completed / rejected / cancelled).
_OPEN_STATUSES = (
    BookingStatus.pending,
    BookingStatus.accepted,
    BookingStatus.on_the_way,
    BookingStatus.arrived,
)


def _pick_provider(db: Session, service_category: str) -> User | None:
    """
    Chooses which provider a new booking is assigned to, now that
    customers pick a service rather than a person.

    Eligible: providers whose profile offers this service, who are marked
    available, and — critically — whose account an admin has already
    verified. A pending or rejected provider is never assigned a new
    booking in the first place: since they're also blocked from accepting
    one (see update_booking_status below), assigning them one anyway would
    only leave it stuck, unacceptable by anyone, until the customer gives
    up and cancels. Among the remaining, eligible providers, the order of
    preference is:
      1. the provider with the fewest open bookings (spreads the load),
      2. random, so equally-loaded providers get an even share.

    Returns None when nobody is eligible — the caller turns that into a
    clear error for the customer. In practice this is also what happens
    while every provider for a category is still pending verification;
    that's expected, not a bug.
    """
    open_jobs = (
        db.query(Booking.provider_id.label("provider_id"), func.count(Booking.id).label("open_count"))
        .filter(Booking.status.in_(_OPEN_STATUSES))
        .group_by(Booking.provider_id)
        .subquery()
    )

    query = (
        db.query(User)
        .join(ProviderProfile, ProviderProfile.user_id == User.id)
        .outerjoin(open_jobs, open_jobs.c.provider_id == User.id)
        .filter(
            User.role == UserRole.provider,
            ProviderProfile.service_category == service_category,
            ProviderProfile.verification_status == VerificationStatus.verified,
        )
    )
    # For Electrical/Plumbing the availability switch means "receive EMERGENCY
    # requests" (and shares live location). Turning it off must not also stop
    # ordinary scheduled bookings, so it only gates the other categories.
    if service_category not in EMERGENCY_SERVICE_CATEGORIES:
        query = query.filter(ProviderProfile.availability.is_(True))
    return (
        query
        .order_by(
            func.coalesce(open_jobs.c.open_count, 0),
            func.random(),
        )
        .first()
    )


@router.post("", response_model=BookingOut, status_code=status.HTTP_201_CREATED)
def create_booking(
    payload: BookingCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != UserRole.customer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only customer accounts can create bookings.",
        )

    provider = _pick_provider(db, payload.service_category)
    if not provider:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No {payload.service_category} professional is available right now. Please try again later.",
        )

    # Price comes from the server's catalogue, never from the request — the
    # client has no price field to send. BookingCreateRequest has already
    # rejected a job_title that isn't offered under this category, so a
    # non-None job_title always resolves here.
    job = find_service_job(payload.service_category, payload.job_title) if payload.job_title else None

    booking = Booking(
        customer_id=current_user.id,
        provider_id=provider.id,
        service_category=payload.service_category,
        job_title=job.name if job else None,
        price=job.price if job else None,
        price_type=job.price_type.value if job else None,
        address=payload.address,
        latitude=payload.latitude,
        longitude=payload.longitude,
        customer_latitude=payload.latitude,
        customer_longitude=payload.longitude,
        customer_location_updated_at=datetime.now(timezone.utc),
        problem_description=payload.problem_description,
        notes=payload.notes,
        preferred_date=payload.preferred_date,
        status=BookingStatus.pending,
    )
    db.add(booking)
    db.flush()  # assigns booking.id, needed to link the notifications
    notify_booking_created(db, booking, current_user.full_name)
    db.commit()
    db.refresh(booking)

    return _to_booking_out(booking, current_user.full_name, current_user.phone)


@router.post("/emergency", response_model=BookingOut, status_code=status.HTTP_201_CREATED)
def create_emergency_booking(
    payload: EmergencyBookingCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create an emergency request for the exact provider the customer selected."""
    if current_user.role != UserRole.customer:
        raise HTTPException(status_code=403, detail="Only customer accounts can create bookings.")

    # Same case/whitespace-insensitive matching as the search endpoint, so a
    # category that appeared in the list can always be booked.
    wanted_category = payload.service_category.strip().lower()
    category = next((c for c in EMERGENCY_SERVICE_CATEGORIES if c.lower() == wanted_category), None)
    if category is None:
        raise HTTPException(
            status_code=400,
            detail=f"Emergency service is only available for: {', '.join(EMERGENCY_SERVICE_CATEGORIES)}.",
        )
    payload.service_category = category

    provider = (
        db.query(User)
        .join(ProviderProfile, ProviderProfile.user_id == User.id)
        .filter(User.id == payload.provider_id, User.role == UserRole.provider)
        .first()
    )
    if not provider:
        raise HTTPException(status_code=404, detail="Service provider not found.")

    # Lock the provider's profile for the rest of this transaction so two
    # customers can't both pass the availability/busy checks for the same
    # provider at the same moment.
    profile = (
        db.query(ProviderProfile)
        .filter(ProviderProfile.user_id == provider.id)
        .with_for_update()
        .first()
    )
    if (
        not profile
        or (profile.service_category or "").strip().lower() != payload.service_category.strip().lower()
        or not profile.availability
        or profile.verification_status != VerificationStatus.verified
        or profile.latitude is None
        or profile.longitude is None
        or profile.location_updated_at is None
    ):
        raise HTTPException(status_code=409, detail="This provider is no longer available for emergency service.")

    location_updated = profile.location_updated_at
    if location_updated.tzinfo is None:
        location_updated = location_updated.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) - location_updated > EMERGENCY_LOCATION_MAX_AGE:
        raise HTTPException(status_code=409, detail="This provider's live location is no longer current.")

    # The provider may have accepted someone else's job since the customer's
    # list was loaded.
    if provider_has_active_job(db, provider.id):
        raise HTTPException(
            status_code=409,
            detail="This provider has just taken another job. Please choose another provider.",
        )

    # Guards against a double-tap / retry creating the same request twice.
    already_requested = (
        db.query(Booking.id)
        .filter(
            Booking.customer_id == current_user.id,
            Booking.provider_id == provider.id,
            Booking.is_emergency.is_(True),
            Booking.status == BookingStatus.pending,
        )
        .first()
    )
    if already_requested:
        raise HTTPException(
            status_code=409,
            detail="You already have a pending emergency request with this provider.",
        )

    # Price comes from the server catalogue, never from the client. The
    # schema has already confirmed the job exists under this category.
    job = find_service_job(payload.service_category, payload.job_title)
    if job is None:
        raise HTTPException(status_code=400, detail="That job is not offered under this service.")

    booking = Booking(
        customer_id=current_user.id,
        provider_id=provider.id,
        service_category=payload.service_category,
        job_title=job.name,
        price=job.price,
        price_type=job.price_type.value,
        address=payload.address,
        latitude=payload.latitude,
        longitude=payload.longitude,
        customer_latitude=payload.latitude,
        customer_longitude=payload.longitude,
        customer_location_updated_at=datetime.now(timezone.utc),
        problem_description=payload.problem_description,
        notes=payload.notes,
        preferred_date=datetime.now(timezone.utc),
        status=BookingStatus.pending,
        provider_latitude=profile.latitude,
        provider_longitude=profile.longitude,
        provider_location_updated_at=profile.location_updated_at,
        is_emergency=True,
    )
    db.add(booking)
    db.flush()
    notify_booking_created(db, booking, current_user.full_name)
    db.commit()
    db.refresh(booking)
    return _to_booking_out(booking, current_user.full_name, current_user.phone)


@router.get("/me", response_model=list[BookingOut])
def list_my_bookings(
    status_filter: BookingStatus | None = Query(default=None, alias="status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    Customer = aliased(User)

    query = (
        db.query(Booking, Customer.full_name, Customer.phone, Rating)
        .join(Customer, Booking.customer_id == Customer.id)
        .outerjoin(Rating, Rating.booking_id == Booking.id)
    )

    if current_user.role == UserRole.customer:
        query = query.filter(Booking.customer_id == current_user.id)
    else:
        query = query.filter(Booking.provider_id == current_user.id)

    if status_filter is not None:
        query = query.filter(Booking.status == status_filter)

    query = query.order_by(Booking.created_at.desc())

    return [
        _to_booking_out(booking, customer_name, customer_phone, rating)
        for booking, customer_name, customer_phone, rating in query.all()
    ]


def _get_owned_booking(db: Session, booking_id: uuid.UUID, current_user: User) -> Booking:
    """Shared lookup for the single-booking endpoints below: 404 if the
    booking doesn't exist, 403 if it exists but isn't the caller's own
    (as either its customer or its assigned provider)."""
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found.")

    is_provider = current_user.role == UserRole.provider and booking.provider_id == current_user.id
    is_customer = current_user.role == UserRole.customer and booking.customer_id == current_user.id
    if not is_provider and not is_customer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to view this booking.",
        )
    return booking


@router.get("/{booking_id}", response_model=BookingOut)
def get_booking(
    booking_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Fetches a single booking — used for cheap, frequent polling (e.g. the
    customer's app checking whether the provider's live location has moved)
    where re-fetching the whole /me list would be wasteful.
    """
    booking = _get_owned_booking(db, booking_id, current_user)
    customer = db.query(User).filter(User.id == booking.customer_id).first()
    rating = db.query(Rating).filter(Rating.booking_id == booking.id).first()
    return _to_booking_out(booking, customer.full_name, customer.phone, rating)


@router.put("/{booking_id}/customer-location", response_model=BookingOut)
def update_customer_location(
    booking_id: uuid.UUID,
    payload: CustomerLocationUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    if current_user.role != UserRole.customer or booking.customer_id != current_user.id:
        raise HTTPException(status_code=403, detail="You don't have permission to update this booking's location.")
    if booking.status not in _LOCATION_SHARING_STATUSES:
        raise HTTPException(status_code=400, detail="Customer location can only be shared for an active booking.")

    booking.customer_latitude = payload.latitude
    booking.customer_longitude = payload.longitude
    booking.customer_location_updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(booking)
    return _to_booking_out(booking, current_user.full_name, current_user.phone)


@router.put("/{booking_id}/location", response_model=BookingOut)
def update_booking_location(
    booking_id: uuid.UUID,
    payload: BookingLocationUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Called repeatedly by the provider's own device while they're en route,
    to keep the booking's live-location fields current. Only the assigned
    provider may push their own location, and only while the booking is
    actually in a state where navigation makes sense — a stray update
    against a pending or completed booking is rejected rather than
    silently accepted.
    """
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found.")

    if current_user.role != UserRole.provider or booking.provider_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to update this booking's location.",
        )

    if booking.status not in _LOCATION_SHARING_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Live location can only be shared while a job is on the way or arrived.",
        )

    booking.provider_latitude = payload.latitude
    booking.provider_longitude = payload.longitude
    booking.provider_location_updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(booking)

    customer = db.query(User).filter(User.id == booking.customer_id).first()
    return _to_booking_out(booking, customer.full_name, customer.phone)


@router.patch("/{booking_id}/status", response_model=BookingOut)
def update_booking_status(
    booking_id: uuid.UUID,
    payload: BookingStatusUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found.")

    new_status = payload.status
    is_provider = current_user.role == UserRole.provider and booking.provider_id == current_user.id
    is_customer = current_user.role == UserRole.customer and booking.customer_id == current_user.id

    if not is_provider and not is_customer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to update this booking.",
        )

    # A provider may only ever accept a booking once an admin has verified
    # their account. _pick_provider already only assigns new bookings to
    # verified providers, so in the ordinary case this never even fires —
    # this exists for the same reason the Flutter UI hides/disables the
    # Accept button for an unverified provider: as a second, server-side
    # guarantee that can't be bypassed by calling the API directly,
    # covering the edge case where an admin reverts a provider's
    # verification after a booking was already assigned to them.
    if is_provider and booking.status == BookingStatus.pending and new_status == BookingStatus.accepted:
        provider_profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).first()
        if not provider_profile or provider_profile.verification_status != VerificationStatus.verified:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your account is pending verification. You can't accept bookings until an admin verifies your profile.",
            )

    # Only specific, sane status transitions are allowed, per role. The
    # provider's happy path is a strict sequence — accepted -> on_the_way
    # -> arrived -> completed — so the customer's status timeline always
    # advances one visible step at a time instead of jumping straight
    # from "Accepted" to "Completed".
    allowed = False
    if is_provider:
        if booking.status == BookingStatus.pending and new_status in (
            BookingStatus.accepted,
            BookingStatus.rejected,
        ):
            allowed = True
        elif booking.status == BookingStatus.accepted and new_status == BookingStatus.on_the_way:
            allowed = True
        elif booking.status == BookingStatus.on_the_way and new_status == BookingStatus.arrived:
            allowed = True
        elif booking.status == BookingStatus.arrived and new_status == BookingStatus.completed:
            if booking.payment_status != "paid":
                raise HTTPException(
                    status_code=status.HTTP_402_PAYMENT_REQUIRED,
                    detail="Payment must be completed before the provider can mark this booking as completed.",
                )
            allowed = True
    elif is_customer:
        if booking.status == BookingStatus.pending and new_status == BookingStatus.cancelled:
            allowed = True

    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot change booking from '{booking.status.value}' to '{new_status.value}'.",
        )

    booking.status = new_status

    if new_status == BookingStatus.accepted and is_provider:
        provider_profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).first()
        if provider_profile and provider_profile.latitude is not None and provider_profile.longitude is not None:
            booking.provider_latitude = provider_profile.latitude
            booking.provider_longitude = provider_profile.longitude
            booking.provider_location_updated_at = provider_profile.location_updated_at or datetime.now(timezone.utc)

    # Stop live location sharing the moment a job is marked completed: clear
    # the fields rather than just leaving the frontend to ignore them, so a
    # finished booking can never be polled into showing a stale position.
    # (No other transition here can leave `_LOCATION_SHARING_STATUSES`,
    # since 'on_the_way' -> 'arrived' -> 'completed' is the only path out.)
    if new_status == BookingStatus.completed:
        booking.provider_latitude = None
        booking.provider_longitude = None
        booking.provider_location_updated_at = None
        booking.customer_latitude = None
        booking.customer_longitude = None
        booking.customer_location_updated_at = None

    customer = db.query(User).filter(User.id == booking.customer_id).first()
    notify_status_change(db, booking, new_status, customer.full_name)

    db.commit()
    db.refresh(booking)

    # A rating (which can only be created once a booking is completed, via
    # the separate /rating endpoint below) never exists yet at the moment
    # a booking *first* transitions to 'completed' here — nothing to fetch.
    return _to_booking_out(booking, customer.full_name, customer.phone)


PENDING_PAYMENT_TTL = timedelta(minutes=10)


def _expire_stale_pending(db: Session, booking: Booking) -> None:
    """Release a payment that was started but never finished.

    A booking is marked "pending" the moment the customer taps Pay. If the
    app crashes, the request fails, or the customer walks away, nothing ever
    clears it and the provider is blocked from editing charges forever.
    """
    if booking.payment_status != "pending":
        return
    updated = booking.payment_updated_at
    if updated is not None:
        if updated.tzinfo is None:
            updated = updated.replace(tzinfo=timezone.utc)
        if datetime.now(timezone.utc) - updated < PENDING_PAYMENT_TTL:
            return
    db.query(PaymentAttempt).filter(
        PaymentAttempt.booking_id == booking.id,
        PaymentAttempt.status == "pending",
    ).update({"status": "cancelled"})
    booking.payment_status = "cancelled"
    booking.payment_transaction_uuid = None
    booking.payment_updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(booking)


@router.patch("/{booking_id}/charges", response_model=BookingOut)
def update_booking_charges(
    booking_id: uuid.UUID,
    payload: ExtraChargeUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Provider sets the additional amount before the customer pays."""
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    if current_user.role != UserRole.provider or booking.provider_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the assigned provider can add charges.")
    if booking.status not in (BookingStatus.accepted, BookingStatus.on_the_way, BookingStatus.arrived):
        raise HTTPException(status_code=400, detail="Additional charges can only be added to an active booking.")
    if booking.payment_status == "paid":
        raise HTTPException(status_code=400, detail="Additional charges cannot be changed after payment.")
    _expire_stale_pending(db, booking)
    if booking.payment_status == "pending":
        raise HTTPException(status_code=409, detail="A payment is already in progress. Finish or cancel it before changing charges.")

    booking.extra_charges = Decimal(str(payload.extra_charges)).quantize(Decimal("0.01"))
    booking.extra_charge_note = payload.note.strip() if payload.note and payload.note.strip() else None
    db.commit()
    db.refresh(booking)
    customer = db.query(User).filter(User.id == booking.customer_id).first()
    return _to_booking_out(booking, customer.full_name, customer.phone)


@router.post("/{booking_id}/payment/cash/received", response_model=BookingOut)
def mark_cash_received(
    booking_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The assigned provider confirms the customer paid them in cash.

    Marks the booking paid (method "cash"), which is exactly what the
    completion rule checks, so the provider can then mark it completed.
    Only possible once the provider has arrived, and never on top of an
    online payment that is paid or still in progress.
    """
    # Locked, like the eSewa verification path, so a cash confirmation and an
    # eSewa result landing together cannot both be applied.
    booking = db.query(Booking).filter(Booking.id == booking_id).with_for_update().first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    if current_user.role != UserRole.provider or booking.provider_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the assigned provider can confirm a cash payment.")
    if booking.status != BookingStatus.arrived:
        raise HTTPException(
            status_code=400,
            detail="You can confirm a cash payment once you have arrived at the customer's location.",
        )
    if booking.payment_status == "paid":
        raise HTTPException(status_code=409, detail="This booking has already been paid.")
    _expire_stale_pending(db, booking)
    if booking.payment_status == "pending":
        raise HTTPException(
            status_code=409,
            detail="The customer is in the middle of an online payment. Wait a few minutes or ask them to cancel it first.",
        )

    # Drop any unfinished eSewa attempt so it can't flip this booking later.
    db.query(PaymentAttempt).filter(
        PaymentAttempt.booking_id == booking.id,
        PaymentAttempt.status == "pending",
    ).update({"status": "cancelled"})

    booking.payment_status = "paid"
    booking.payment_method = "cash"
    booking.payment_reference = None
    booking.payment_transaction_uuid = None
    booking.payment_updated_at = datetime.now(timezone.utc)

    customer = db.query(User).filter(User.id == booking.customer_id).first()
    notify_cash_received(db, booking, customer.full_name)

    db.commit()
    db.refresh(booking)
    return _to_booking_out(booking, customer.full_name, customer.phone)


def _get_customer_booking(db: Session, booking_id: uuid.UUID, current_user: User) -> Booking:
    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    if current_user.role != UserRole.customer or booking.customer_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the customer who owns this booking can pay for it.")
    return booking


def _apply_esewa_response(db: Session, attempt: PaymentAttempt, response_data: dict) -> PaymentAttempt:
    """Verify the signed response and eSewa's authoritative status.

    A booking is only ever marked paid when eSewa's own status API reports
    COMPLETE for this exact transaction, product and amount. The redirect
    data from the app is never trusted on its own.
    """
    if not verify_response_signature(response_data):
        raise HTTPException(status_code=400, detail="Invalid eSewa response signature.")

    transaction_uuid = str(response_data.get("transaction_uuid", ""))
    product_code = str(response_data.get("product_code", ""))
    try:
        # eSewa may format the amount with thousands separators ("1,000.0").
        total_amount = Decimal(str(response_data.get("total_amount", "0")).replace(",", "")).quantize(Decimal("0.01"))
    except Exception:
        raise HTTPException(status_code=400, detail="eSewa returned an invalid amount.")

    if transaction_uuid != attempt.transaction_uuid or product_code != settings.esewa_product_code:
        raise HTTPException(status_code=400, detail="eSewa transaction does not match this booking.")
    # The attempt's amount was fixed server-side when the payment started.
    if total_amount != Decimal(str(attempt.amount)).quantize(Decimal("0.01")):
        raise HTTPException(status_code=400, detail="eSewa amount does not match the booking total.")

    # Already confirmed (e.g. the app's /verify call and eSewa's server
    # callback both arrive): nothing more to ask eSewa.
    if attempt.status == "paid":
        return attempt

    # Ask eSewa BEFORE locking the booking row. This is a slow network call;
    # holding the lock across it blocks every other write to the booking,
    # including the live-location updates emergency bookings send every few
    # seconds, which stalls them and can make this very request time out.
    try:
        status_response = status_check(transaction_uuid, total_amount)
    except PaymentGatewayError:
        logger.exception("eSewa status check failed for %s", transaction_uuid)
        raise HTTPException(
            status_code=502,
            detail="Could not confirm the payment with eSewa yet. Please tap Retry in a moment.",
        )
    provider_status = str(status_response.get("status", "")).upper()
    returned_product = status_response.get("product_code") or status_response.get("scd")
    if returned_product is not None and str(returned_product) != settings.esewa_product_code:
        raise HTTPException(status_code=400, detail="eSewa status response has the wrong product code.")
    status_txn = status_response.get("transaction_uuid")
    if status_txn is not None and str(status_txn) != transaction_uuid:
        raise HTTPException(status_code=400, detail="eSewa status response has the wrong transaction.")
    status_amount = status_response.get("total_amount") or status_response.get("totalAmount")
    if status_amount is not None and Decimal(str(status_amount).replace(",", "")).quantize(Decimal("0.01")) != total_amount:
        raise HTTPException(status_code=400, detail="eSewa status response has the wrong amount.")

    # Now take the row lock, only for the short write.
    booking = db.query(Booking).filter(Booking.id == attempt.booking_id).with_for_update().first()
    if not booking:
        raise HTTPException(status_code=404, detail="Booking not found.")
    db.refresh(attempt)
    expected_total = (Decimal(str(booking.price or 0)) + Decimal(str(booking.extra_charges or 0))).quantize(Decimal("0.01"))
    if total_amount != expected_total:
        raise HTTPException(status_code=400, detail="eSewa amount does not match the booking total.")

    # Both the app's /verify call and eSewa's server callback can land here
    # for the same payment; only the first one to flip it to "paid" should
    # notify, so remember whether it already was (the row is locked above).
    was_already_paid = booking.payment_status == "paid"

    attempt.raw_response = json.dumps({"redirect": response_data, "status_check": status_response})
    attempt.reference = (status_response.get("ref_id") or status_response.get("refId")
                         or response_data.get("transaction_code"))
    attempt.status = {
        "COMPLETE": "paid",
        "CANCELED": "cancelled",
        "FULL_REFUND": "refunded",
        "PARTIAL_REFUND": "refunded",
        "PENDING": "pending",
        "AMBIGUOUS": "pending",
        "NOT_FOUND": "failed",
    }.get(provider_status, "failed")

    if attempt.status == "paid":
        booking.payment_status = "paid"
        booking.payment_transaction_uuid = attempt.transaction_uuid
        booking.payment_reference = attempt.reference
        booking.payment_method = "esewa"
    elif booking.payment_status != "paid":
        booking.payment_status = attempt.status
        if attempt.status in {"cancelled", "failed"}:
            booking.payment_transaction_uuid = None
    booking.payment_updated_at = datetime.now(timezone.utc)

    if attempt.status == "paid" and not was_already_paid:
        customer = db.query(User).filter(User.id == booking.customer_id).first()
        notify_payment_successful(db, booking, customer.full_name)

    db.commit()
    db.refresh(attempt)
    return attempt


@router.post("/{booking_id}/payment/esewa/initiate", response_model=EsewaPaymentInitOut)
def initiate_esewa_payment(
    booking_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = _get_customer_booking(db, booking_id, current_user)
    if booking.price is None:
        raise HTTPException(status_code=400, detail="This booking does not have a payable price.")
    if booking.status in (BookingStatus.rejected, BookingStatus.cancelled, BookingStatus.completed):
        raise HTTPException(status_code=400, detail="This booking is no longer payable.")
    if booking.payment_status == "paid":
        raise HTTPException(status_code=409, detail="This booking has already been paid.")

    # A new attempt supersedes any earlier unfinished one for this booking.
    db.query(PaymentAttempt).filter(
        PaymentAttempt.booking_id == booking.id,
        PaymentAttempt.status == "pending",
    ).update({"status": "cancelled"})

    total = (Decimal(str(booking.price)) + Decimal(str(booking.extra_charges or 0))).quantize(Decimal("0.01"))
    transaction_uuid = f"{booking.id.hex[:20]}-{uuid.uuid4().hex[:12]}"
    fields = {
        # eSewa requires total_amount == amount + tax_amount +
        # product_service_charge + product_delivery_charge (else ES704), so
        # "amount" must already include any extra charges.
        "amount": money(total),
        "tax_amount": "0",
        "total_amount": money(total),
        "product_service_charge": "0",
        "product_delivery_charge": "0",
        "product_code": settings.esewa_product_code,
        "transaction_uuid": transaction_uuid,
        "success_url": f"{settings.esewa_public_base_url.rstrip('/')}/api/bookings/esewa/success?booking_id={booking.id}&transaction_uuid={transaction_uuid}",
        "failure_url": f"{settings.esewa_public_base_url.rstrip('/')}/api/bookings/esewa/failure?booking_id={booking.id}&transaction_uuid={transaction_uuid}",
        "signed_field_names": settings.esewa_signed_field_names,
    }
    fields["signature"] = sign_fields(fields)

    attempt = PaymentAttempt(
        booking_id=booking.id,
        transaction_uuid=transaction_uuid,
        amount=total,
        status="pending",
    )
    db.add(attempt)
    booking.payment_status = "pending"
    booking.payment_transaction_uuid = transaction_uuid
    booking.payment_updated_at = datetime.now(timezone.utc)
    db.commit()

    return EsewaPaymentInitOut(
        booking_id=booking.id,
        transaction_uuid=transaction_uuid,
        amount=float(booking.price),
        extra_charges=float(booking.extra_charges or 0),
        total_amount=float(total),
        form_url=settings.esewa_form_url,
        fields=fields,
    )


@router.post("/{booking_id}/payment/esewa/verify", response_model=BookingOut)
def verify_esewa_payment(
    booking_id: uuid.UUID,
    payload: EsewaVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = _get_customer_booking(db, booking_id, current_user)
    try:
        response_data = decode_response(payload.data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid eSewa payment response.")

    txn = str(response_data.get("transaction_uuid", ""))
    attempt = db.query(PaymentAttempt).filter(
        PaymentAttempt.booking_id == booking.id,
        PaymentAttempt.transaction_uuid == txn,
    ).first()
    if not attempt:
        raise HTTPException(status_code=404, detail="Payment attempt not found.")

    _apply_esewa_response(db, attempt, response_data)
    db.refresh(booking)
    return _to_booking_out(booking, current_user.full_name, current_user.phone)


@router.post("/{booking_id}/payment/esewa/cancel", response_model=BookingOut)
def cancel_esewa_payment(
    booking_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    booking = _get_customer_booking(db, booking_id, current_user)
    if booking.payment_status == "paid":
        raise HTTPException(status_code=409, detail="A successful payment cannot be cancelled here.")
    if booking.payment_transaction_uuid:
        attempt = db.query(PaymentAttempt).filter(
            PaymentAttempt.transaction_uuid == booking.payment_transaction_uuid
        ).first()
        if attempt and attempt.status == "pending":
            attempt.status = "cancelled"
    booking.payment_status = "cancelled"
    booking.payment_transaction_uuid = None
    booking.payment_updated_at = datetime.now(timezone.utc)
    db.commit()
    return _to_booking_out(booking, current_user.full_name, current_user.phone)


def _esewa_callback_html(title: str, message: str) -> HTMLResponse:
    return HTMLResponse(f"""<!doctype html><html><body style='font-family:sans-serif;padding:32px'><h2>{title}</h2><p>{message}</p><p>You can return to GharSewa.</p></body></html>""")


@router.get("/esewa/success", response_class=HTMLResponse, include_in_schema=False)
def esewa_success_callback(
    booking_id: uuid.UUID,
    transaction_uuid: str,
    data: str | None = None,
    db: Session = Depends(get_db),
):
    """Server callback/fallback: verify a success redirect even if the app is closed."""
    # eSewa appends "?data=..." to success_url even when it already has a
    # query string, so the data can end up glued onto transaction_uuid.
    if "?data=" in transaction_uuid:
        transaction_uuid, _, embedded = transaction_uuid.partition("?data=")
        data = data or embedded
    if not data:
        return _esewa_callback_html("Payment received", "The payment response is being verified.")
    try:
        response_data = decode_response(data)
        attempt = db.query(PaymentAttempt).filter(
            PaymentAttempt.booking_id == booking_id,
            PaymentAttempt.transaction_uuid == transaction_uuid,
        ).first()
        if attempt:
            confirmed = _apply_esewa_response(db, attempt, response_data)
            if confirmed.status == "paid":
                return _esewa_callback_html("Payment verified", "Your GharSewa payment was verified successfully.")
    except Exception:
        db.rollback()
    return _esewa_callback_html("Payment verification pending", "Please return to GharSewa and check the payment status.")


@router.get("/esewa/failure", response_class=HTMLResponse, include_in_schema=False)
def esewa_failure_callback(
    booking_id: uuid.UUID,
    transaction_uuid: str,
    db: Session = Depends(get_db),
):
    transaction_uuid = transaction_uuid.split("?")[0]
    attempt = db.query(PaymentAttempt).filter(
        PaymentAttempt.booking_id == booking_id,
        PaymentAttempt.transaction_uuid == transaction_uuid,
    ).first()
    # Only a real, still-open attempt can be failed. Without this check anyone
    # who knew a booking id could mark its payment as failed, and a late
    # callback for an old attempt could clobber a newer one in progress.
    if attempt and attempt.status == "pending":
        attempt.status = "failed"
        booking = db.query(Booking).filter(Booking.id == booking_id).with_for_update().first()
        if booking and booking.payment_status != "paid" and booking.payment_transaction_uuid == attempt.transaction_uuid:
            booking.payment_status = "failed"
            booking.payment_transaction_uuid = None
            booking.payment_updated_at = datetime.now(timezone.utc)
        db.commit()
    return _esewa_callback_html("Payment not completed", "The eSewa payment was cancelled or failed. No booking completion was recorded.")


@router.post("/{booking_id}/rating", response_model=BookingOut, status_code=status.HTTP_201_CREATED)
def rate_booking(
    booking_id: uuid.UUID,
    payload: RatingCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != UserRole.customer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only customers can rate a service.",
        )

    booking = db.query(Booking).filter(Booking.id == booking_id).first()
    if not booking:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found.")

    if booking.customer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only rate your own bookings.",
        )

    if booking.status != BookingStatus.completed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You can only rate a booking once the work is marked as completed.",
        )

    existing = db.query(Rating).filter(Rating.booking_id == booking_id).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already rated this booking.",
        )

    rating = Rating(
        booking_id=booking.id,
        customer_id=booking.customer_id,
        service_category=booking.service_category,
        stars=payload.stars,
        comment=payload.comment,
    )
    db.add(rating)
    try:
        db.commit()
    except IntegrityError:
        # Covers the (rare) race where two requests for the same booking
        # both pass the "existing" check above before either commits —
        # the DB-level unique constraint on booking_id is the real
        # guarantee that a booking is only ever rated once.
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You have already rated this booking.",
        )
    db.refresh(rating)

    # No aggregate to update here: a service's overall rating is computed
    # on read from the ratings table (see routers/services.py), so it is
    # always exactly consistent with the ratings that exist.
    return _to_booking_out(booking, current_user.full_name, current_user.phone, rating)