import re
import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.models import BookingStatus, UserRole, VerificationStatus

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
    experience: int | None
    address: str | None
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
    experience: int | None = Field(default=None, ge=0, le=80)
    availability: bool | None = None


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

    model_config = {"from_attributes": True}