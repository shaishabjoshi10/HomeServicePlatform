from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import CustomerProfile, ProviderProfile, User, UserRole
from app.schemas import AuthResponse, LoginRequest, SignupRequest
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _split_identifier(identifier: str) -> tuple[str | None, str | None]:
    """Return (email, phone) based on whether the identifier looks like an email."""
    if "@" in identifier:
        return identifier, None
    return None, identifier


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(payload: SignupRequest, db: Session = Depends(get_db)):
    email, phone = _split_identifier(payload.identifier)

    existing = (
        db.query(User)
        .filter(
            User.role == payload.role,
            or_(
                (User.email == email) if email else False,
                (User.phone == phone) if phone else False,
            ),
        )
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"An account with this {'email' if email else 'phone number'} already exists for this role.",
        )

    user = User(
        full_name=payload.full_name.strip(),
        email=email,
        phone=phone,
        password_hash=hash_password(payload.password),
        role=payload.role,
    )
    db.add(user)

    try:
        db.flush()  # assigns user.id without committing yet
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with these details already exists for this role.",
        )

    # Every signup gets a matching profile row — customer_profiles or
    # provider_profiles — created empty/minimal and filled in later via
    # the profile edit flow.
    if payload.role == UserRole.customer:
        db.add(CustomerProfile(user_id=user.id, name=user.full_name))
    else:
        # service_category is no longer collected at signup — the provider
        # sets it later via the profile edit flow (PUT /api/profile/me).
        db.add(ProviderProfile(user_id=user.id, name=user.full_name))

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with these details already exists for this role.",
        )
    db.refresh(user)

    token = create_access_token(subject=str(user.id), role=user.role.value)
    return AuthResponse(access_token=token, user=user)


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    email, phone = _split_identifier(payload.identifier)

    user = (
        db.query(User)
        .filter(
            User.role == payload.role,
            or_(
                (User.email == email) if email else False,
                (User.phone == phone) if phone else False,
            ),
        )
        .first()
    )

    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email/phone or password.",
        )

    token = create_access_token(subject=str(user.id), role=user.role.value)
    return AuthResponse(access_token=token, user=user)