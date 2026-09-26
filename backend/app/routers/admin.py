import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_admin
from app.models import (
    Admin,
    Booking,
    BookingStatus,
    CustomerProfile,
    ProviderProfile,
    User,
    UserRole,
    VerificationStatus,
)
from app.schemas import (
    AdminAuthResponse,
    AdminCustomerOut,
    AdminLoginRequest,
    AdminOut,
    AdminProviderDetailOut,
    AdminProviderOut,
    AdminStatsOut,
    AdminVerificationUpdateRequest,
)
from app.security import create_access_token, verify_password

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.post("/login", response_model=AdminAuthResponse)
def admin_login(payload: AdminLoginRequest, db: Session = Depends(get_db)):
    admin = db.query(Admin).filter(Admin.email == payload.email).first()

    # Same "don't reveal which part was wrong" shape as the customer/
    # provider login in routers/auth.py, and the same constant-time
    # comparison via verify_password() either way — including when no
    # admin row matches, so a bad email doesn't respond measurably faster
    # than a bad password would.
    if not admin or not verify_password(payload.password, admin.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect admin email or password.",
        )

    token = create_access_token(subject=str(admin.id), role="admin")
    return AdminAuthResponse(access_token=token, admin=AdminOut.model_validate(admin))


@router.get("/stats", response_model=AdminStatsOut)
def get_admin_stats(
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    total_customers = db.query(func.count(User.id)).filter(User.role == UserRole.customer).scalar() or 0
    total_providers = db.query(func.count(User.id)).filter(User.role == UserRole.provider).scalar() or 0

    verification_counts = dict(
        db.query(ProviderProfile.verification_status, func.count(ProviderProfile.id))
        .group_by(ProviderProfile.verification_status)
        .all()
    )
    total_bookings = db.query(func.count(Booking.id)).scalar() or 0

    return AdminStatsOut(
        total_customers=total_customers,
        total_providers=total_providers,
        pending_verifications=verification_counts.get(VerificationStatus.pending, 0),
        verified_providers=verification_counts.get(VerificationStatus.verified, 0),
        rejected_providers=verification_counts.get(VerificationStatus.rejected, 0),
        total_bookings=total_bookings,
    )


@router.get("/customers", response_model=list[AdminCustomerOut])
def list_customers(
    q: str | None = Query(default=None, max_length=200, description="Search by name, email or phone"),
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    booking_count = func.count(Booking.id).label("booking_count")
    query = (
        db.query(User, CustomerProfile, booking_count)
        .join(CustomerProfile, CustomerProfile.user_id == User.id)
        .outerjoin(Booking, Booking.customer_id == User.id)
        .filter(User.role == UserRole.customer)
    )

    if q and q.strip():
        like = f"%{q.strip()}%"
        query = query.filter(
            or_(User.full_name.ilike(like), User.email.ilike(like), User.phone.ilike(like))
        )

    rows = query.group_by(User.id, CustomerProfile.id).order_by(User.created_at.desc()).all()

    return [
        AdminCustomerOut(
            id=user.id,
            full_name=user.full_name,
            email=user.email,
            phone=user.phone,
            created_at=user.created_at,
            address=profile.address,
            profile_picture_url=profile.profile_picture_url,
            total_bookings=count,
        )
        for user, profile, count in rows
    ]


@router.get("/providers", response_model=list[AdminProviderOut])
def list_providers(
    q: str | None = Query(default=None, max_length=200, description="Search by name, email, phone or service"),
    verification_status: VerificationStatus | None = Query(default=None),
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    booking_count = func.count(Booking.id).label("booking_count")
    query = (
        db.query(User, ProviderProfile, booking_count)
        .join(ProviderProfile, ProviderProfile.user_id == User.id)
        .outerjoin(Booking, Booking.provider_id == User.id)
        .filter(User.role == UserRole.provider)
    )

    if verification_status is not None:
        query = query.filter(ProviderProfile.verification_status == verification_status)

    if q and q.strip():
        like = f"%{q.strip()}%"
        query = query.filter(
            or_(
                User.full_name.ilike(like),
                User.email.ilike(like),
                User.phone.ilike(like),
                ProviderProfile.service_category.ilike(like),
            )
        )

    rows = query.group_by(User.id, ProviderProfile.id).order_by(User.created_at.desc()).all()

    return [
        AdminProviderOut(
            id=user.id,
            full_name=user.full_name,
            email=user.email,
            phone=user.phone,
            created_at=user.created_at,
            service_category=profile.service_category,
            experience=profile.experience,
            city=profile.city,
            verification_status=profile.verification_status,
            availability=profile.availability,
            profile_picture_url=profile.profile_picture_url,
            total_bookings=count,
        )
        for user, profile, count in rows
    ]


def _get_provider_user_and_profile(db: Session, provider_id: uuid.UUID) -> tuple[User, ProviderProfile]:
    user = db.query(User).filter(User.id == provider_id, User.role == UserRole.provider).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider not found.")

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == provider_id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider profile not found.")

    return user, profile


def _to_provider_detail(db: Session, user: User, profile: ProviderProfile) -> AdminProviderDetailOut:
    total_bookings = db.query(func.count(Booking.id)).filter(Booking.provider_id == user.id).scalar() or 0
    completed_bookings = (
        db.query(func.count(Booking.id))
        .filter(Booking.provider_id == user.id, Booking.status == BookingStatus.completed)
        .scalar()
        or 0
    )

    return AdminProviderDetailOut(
        id=user.id,
        full_name=user.full_name,
        email=user.email,
        phone=user.phone,
        created_at=user.created_at,
        service_category=profile.service_category,
        experience=profile.experience,
        bio=profile.bio,
        date_of_birth=profile.date_of_birth,
        city=profile.city,
        citizenship_number=profile.citizenship_number,
        citizenship_front_url=profile.citizenship_front_url,
        citizenship_back_url=profile.citizenship_back_url,
        alternative_email=profile.alternative_email,
        alternative_phone=profile.alternative_phone,
        profile_picture_url=profile.profile_picture_url,
        verification_status=profile.verification_status,
        availability=profile.availability,
        total_bookings=total_bookings,
        completed_bookings=completed_bookings,
    )


@router.get("/providers/{provider_id}", response_model=AdminProviderDetailOut)
def get_provider_detail(
    provider_id: uuid.UUID,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    user, profile = _get_provider_user_and_profile(db, provider_id)
    return _to_provider_detail(db, user, profile)


@router.patch("/providers/{provider_id}/verification", response_model=AdminProviderDetailOut)
def update_provider_verification(
    provider_id: uuid.UUID,
    payload: AdminVerificationUpdateRequest,
    admin: Admin = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    The one action this whole dashboard exists for: an admin verifying or
    rejecting a provider's submitted documents. Deliberately narrow — see
    AdminVerificationUpdateRequest for why 'pending' isn't a valid target
    here.
    """
    user, profile = _get_provider_user_and_profile(db, provider_id)

    profile.verification_status = payload.status
    db.commit()
    db.refresh(profile)

    return _to_provider_detail(db, user, profile)
