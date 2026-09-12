import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.database import get_db
from app.deps import get_current_user
from app.models import Booking, BookingStatus, ProviderProfile, Rating, User, UserRole
from app.schemas import (
    BookingCreateRequest,
    BookingOut,
    BookingStatusUpdateRequest,
    RatingCreateRequest,
)

router = APIRouter(prefix="/api/bookings", tags=["bookings"])


def _to_booking_out(
    booking: Booking,
    customer_name: str,
    provider_name: str,
    rating: Rating | None = None,
) -> BookingOut:
    return BookingOut(
        id=booking.id,
        customer_id=booking.customer_id,
        customer_name=customer_name,
        provider_id=booking.provider_id,
        provider_name=provider_name,
        service_category=booking.service_category,
        address=booking.address,
        latitude=booking.latitude,
        longitude=booking.longitude,
        notes=booking.notes,
        preferred_date=booking.preferred_date,
        status=booking.status,
        created_at=booking.created_at,
        updated_at=booking.updated_at,
        rating_stars=rating.stars if rating else None,
        rating_comment=rating.comment if rating else None,
        rated_at=rating.created_at if rating else None,
    )


def _recompute_provider_rating(db: Session, provider_id: uuid.UUID) -> None:
    """
    Recalculates a provider's cached average rating + review count from
    every Rating row that references them, and writes the result back to
    ProviderProfile.rating / reviews_count.

    Recomputing the aggregate from scratch (rather than updating a
    running average incrementally) is deliberate: it's simple, always
    exactly consistent with the ratings table, and cheap enough at any
    realistic review volume given the index on Rating.provider_id.
    Called once, right after a new rating is committed, so the provider's
    displayed rating updates automatically with no separate step needed.
    """
    avg_stars, review_count = (
        db.query(func.avg(Rating.stars), func.count(Rating.id))
        .filter(Rating.provider_id == provider_id)
        .one()
    )

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == provider_id).first()
    if not profile:
        return

    profile.rating = round(float(avg_stars), 1) if avg_stars is not None else 0.0
    profile.reviews_count = review_count or 0
    db.commit()


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

    provider = db.query(User).filter(User.id == payload.provider_id, User.role == UserRole.provider).first()
    if not provider:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Service provider not found.")

    booking = Booking(
        customer_id=current_user.id,
        provider_id=provider.id,
        service_category=payload.service_category,
        address=payload.address,
        latitude=payload.latitude,
        longitude=payload.longitude,
        notes=payload.notes,
        preferred_date=payload.preferred_date,
        status=BookingStatus.pending,
    )
    db.add(booking)
    db.commit()
    db.refresh(booking)

    return _to_booking_out(booking, current_user.full_name, provider.full_name)


@router.get("/me", response_model=list[BookingOut])
def list_my_bookings(
    status_filter: BookingStatus | None = Query(default=None, alias="status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    Customer = aliased(User)
    Provider = aliased(User)

    query = (
        db.query(Booking, Customer.full_name, Provider.full_name, Rating)
        .join(Customer, Booking.customer_id == Customer.id)
        .join(Provider, Booking.provider_id == Provider.id)
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
        _to_booking_out(booking, customer_name, provider_name, rating)
        for booking, customer_name, provider_name, rating in query.all()
    ]


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

    # Only specific, sane status transitions are allowed, per role.
    allowed = False
    if is_provider:
        if booking.status == BookingStatus.pending and new_status in (
            BookingStatus.accepted,
            BookingStatus.rejected,
        ):
            allowed = True
        elif booking.status == BookingStatus.accepted and new_status == BookingStatus.completed:
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
    db.commit()
    db.refresh(booking)

    customer = db.query(User).filter(User.id == booking.customer_id).first()
    provider = db.query(User).filter(User.id == booking.provider_id).first()

    # No allowed transition above ever lands on/leaves 'completed', so a
    # rating (which can only be created once a booking is completed)
    # never exists at this point — nothing to fetch here.
    return _to_booking_out(booking, customer.full_name, provider.full_name)


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
            detail="Only customers can rate a service provider.",
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
        provider_id=booking.provider_id,
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

    _recompute_provider_rating(db, booking.provider_id)

    provider = db.query(User).filter(User.id == booking.provider_id).first()
    return _to_booking_out(booking, current_user.full_name, provider.full_name, rating)