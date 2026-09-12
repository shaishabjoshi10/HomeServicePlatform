import re
import uuid
from datetime import date, datetime, timezone

from pydantic import BaseModel, Field, field_validator, model_validator

from app.constants import DEFAULT_CITY, EXPERIENCE_RANGES
from app.models import BookingStatus, UserRole, VerificationStatus

# A provider must be at least this old — sanity bound for date_of_birth.
_MIN_PROVIDER_AGE_YEARS = 18

_EMAIL_RE = re.compile(r"^[\w.\-+]+@[\w\-]+\.[a-zA-Z]{2,}$")


def _validate_identifier(v: str) -> str:
    """Shared rule: must look like a valid email, or have >=7 digits if not."""
    v = v.strip().lower()

    if "@" in v:
        if not _EMAIL_RE.match(v):
            raise ValueError("Enter a valid email address")
    else:
        digits_only = re.sub(r"[^0-9]", "", v)
        if len(digits_only) < 7:
            raise ValueError("Enter a valid phone number")

    return v


class SignupRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=255)
    identifier: str = Field(min_length=3, description="Email address or phone number")
    password: str = Field(min_length=6, max_length=128)
    role: UserRole

    @field_validator("identifier")
    @classmethod
    def normalize_identifier(cls, v: str) -> str:
        return _validate_identifier(v)


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=3)
    password: str
    role: UserRole

    @field_validator("identifier")
    @classmethod
    def normalize_identifier(cls, v: str) -> str:
        return _validate_identifier(v)


class UserOut(BaseModel):
    id: uuid.UUID
    full_name: str
    email: str | None
    phone: str | None
    role: UserRole
    created_at: datetime

    model_config = {"from_attributes": True}


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class CustomerProfileOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    address: str | None
    latitude: float | None
    longitude: float | None

    model_config = {"from_attributes": True}


class ProviderProfileOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    service_category: str | None
    experience: str | None
    bio: str | None
    date_of_birth: date | None
    city: str
    citizenship_number: str | None
    citizenship_front_url: str | None
    citizenship_back_url: str | None
    alternative_email: str | None
    alternative_phone: str | None
    verification_status: VerificationStatus
    availability: bool
    rating: float
    reviews_count: int

    model_config = {"from_attributes": True}


class ProviderPublicOut(BaseModel):
    """
    What customers see when browsing providers (GET /api/providers). Unlike
    ProviderProfileOut, this deliberately excludes citizenship details,
    alternative contact info, and precise address — those are only for the
    provider themselves (GET /api/profile/me) and for admin verification.

    user_id IS included (unlike the fields above) because it isn't
    sensitive and the client needs it: booking creation targets a User id
    (Booking.provider_id -> users.id), not this profile's own id.
    """

    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    service_category: str | None
    experience: str | None
    bio: str | None
    city: str
    verification_status: VerificationStatus
    availability: bool
    rating: float
    reviews_count: int

    model_config = {"from_attributes": True}


class ProfileUpdateRequest(BaseModel):
    """
    Single flexible update body used for both roles — fields that don't
    apply to the caller's role (e.g. service_category for a customer)
    are simply ignored server-side.
    """

    name: str | None = Field(default=None, min_length=2, max_length=255)
    address: str | None = Field(default=None, max_length=500)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    service_category: str | None = Field(default=None, max_length=100)
    experience: str | None = Field(default=None, max_length=50)
    bio: str | None = Field(default=None, max_length=500)
    availability: bool | None = None

    # Personal info — provider only. City is not settable here: the app
    # currently only serves DEFAULT_CITY (see app.constants), so it's
    # fixed server-side rather than accepted from the client.
    date_of_birth: date | None = None
    citizenship_number: str | None = Field(default=None, max_length=50)

    # Alternative contact details — provider only.
    alternative_email: str | None = Field(default=None, max_length=255)
    alternative_phone: str | None = Field(default=None, max_length=20)

    @field_validator("experience")
    @classmethod
    def validate_experience(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if v not in EXPERIENCE_RANGES:
            raise ValueError(f"Experience must be one of: {', '.join(EXPERIENCE_RANGES)}")
        return v

    @field_validator("date_of_birth")
    @classmethod
    def validate_date_of_birth(cls, v: date | None) -> date | None:
        if v is None:
            return v
        today = datetime.now(timezone.utc).date()
        if v > today:
            raise ValueError("Date of birth cannot be in the future")
        age_years = (today - v).days // 365
        if age_years < _MIN_PROVIDER_AGE_YEARS:
            raise ValueError(f"Provider must be at least {_MIN_PROVIDER_AGE_YEARS} years old")
        return v

    @field_validator("alternative_email")
    @classmethod
    def validate_alternative_email(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip().lower()
        if not v:
            return None
        if not _EMAIL_RE.match(v):
            raise ValueError("Enter a valid email address")
        return v

    @field_validator("alternative_phone")
    @classmethod
    def validate_alternative_phone(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if not v:
            return None
        digits_only = re.sub(r"[^0-9]", "", v)
        if len(digits_only) < 7:
            raise ValueError("Enter a valid alternative phone number")
        return v


class ProfileOptionsOut(BaseModel):
    """Dropdown option lists for the provider verification form."""

    service_categories: list[str]
    experience_ranges: list[str]
    default_city: str = DEFAULT_CITY


class BookingCreateRequest(BaseModel):
    provider_id: uuid.UUID
    service_category: str | None = Field(default=None, max_length=100)
    address: str = Field(min_length=3, max_length=500)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    notes: str | None = Field(default=None, max_length=1000)
    preferred_date: datetime | None = None


class BookingStatusUpdateRequest(BaseModel):
    status: BookingStatus


class BookingOut(BaseModel):
    id: uuid.UUID
    customer_id: uuid.UUID
    customer_name: str
    provider_id: uuid.UUID
    provider_name: str
    service_category: str | None
    address: str
    latitude: float | None
    longitude: float | None
    notes: str | None
    preferred_date: datetime | None
    status: BookingStatus
    created_at: datetime
    updated_at: datetime

    # Present only once the customer has rated this booking. Kept inline
    # here (rather than a separate "did I rate this?" endpoint) so the
    # booking list can show/hide the "Rate" button with no extra request.
    rating_stars: int | None = None
    rating_comment: str | None = None
    rated_at: datetime | None = None

    model_config = {"from_attributes": True}


class RatingCreateRequest(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=1000)


class RatingOut(BaseModel):
    id: uuid.UUID
    booking_id: uuid.UUID
    customer_id: uuid.UUID
    provider_id: uuid.UUID
    stars: int
    comment: str | None
    created_at: datetime

    model_config = {"from_attributes": True}