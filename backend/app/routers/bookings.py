import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import case, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.constants import find_service_job, format_price_label
from app.database import get_db
from app.deps import get_current_user
from app.models import (
    Booking,
    BookingStatus,
    ProviderProfile,
    Rating,
    User,
    UserRole,
    VerificationStatus,
)
from app.schemas import (
    BookingCreateRequest,
    BookingLocationUpdateRequest,
    BookingOut,
    BookingStatusUpdateRequest,
    RatingCreateRequest,
)

# Statuses during which a provider is expected to be actively navigating to
# the customer, and so is allowed to push live-location updates. Chosen to
# match exactly what the frontend's navigation map keeps rendering (see
# ProviderNavigationMap): it starts tracking on 'on_the_way' and only stops
# once the booking is marked 'completed', passing through 'arrived' in
# between without interruption.
_LOCATION_SHARING_STATUSES = (BookingStatus.on_the_way, BookingStatus.arrived)

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
    available, and whose verification wasn't rejected. Among those, the
    order of preference is:
      1. verified providers before not-yet-verified ones,
      2. the provider with the fewest open bookings (spreads the load),
      3. random, so equally-loaded providers get an even share.

    Returns None when nobody is eligible — the caller turns that into a
    clear error for the customer.
    """
    open_jobs = (
        db.query(Booking.provider_id.label("provider_id"), func.count(Booking.id).label("open_count"))
        .filter(Booking.status.in_(_OPEN_STATUSES))
        .group_by(Booking.provider_id)
        .subquery()
    )

    return (
        db.query(User)
        .join(ProviderProfile, ProviderProfile.user_id == User.id)
        .outerjoin(open_jobs, open_jobs.c.provider_id == User.id)
        .filter(
            User.role == UserRole.provider,
            ProviderProfile.service_category == service_category,
            ProviderProfile.availability.is_(True),
            ProviderProfile.verification_status != VerificationStatus.rejected,
        )
        .order_by(
            case((ProviderProfile.verification_status == VerificationStatus.verified, 0), else_=1),
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
        problem_description=payload.problem_description,
        notes=payload.notes,
        preferred_date=payload.preferred_date,
        status=BookingStatus.pending,
    )
    db.add(booking)
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

    # Stop live location sharing the moment a job is marked completed: clear
    # the fields rather than just leaving the frontend to ignore them, so a
    # finished booking can never be polled into showing a stale position.
    # (No other transition here can leave `_LOCATION_SHARING_STATUSES`,
    # since 'on_the_way' -> 'arrived' -> 'completed' is the only path out.)
    if new_status == BookingStatus.completed:
        booking.provider_latitude = None
        booking.provider_longitude = None
        booking.provider_location_updated_at = None

    db.commit()
    db.refresh(booking)

    customer = db.query(User).filter(User.id == booking.customer_id).first()

    # A rating (which can only be created once a booking is completed, via
    # the separate /rating endpoint below) never exists yet at the moment
    # a booking *first* transitions to 'completed' here — nothing to fetch.
    return _to_booking_out(booking, customer.full_name, customer.phone)


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