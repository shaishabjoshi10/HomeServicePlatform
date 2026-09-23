import re
import uuid
from datetime import date, datetime, timezone

from pydantic import BaseModel, Field, field_validator, model_validator

from app.constants import (
    DEFAULT_CITY,
    EXPERIENCE_RANGES,
    SERVICE_CATEGORIES,
    PriceType,
    find_service_job,
)
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
    profile_picture_url: str | None

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
    profile_picture_url: str | None
    verification_status: VerificationStatus
    availability: bool

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
    """
    Mandatory fields: service_category, address (+ coordinates),
    preferred_date, and problem_description. notes is the only optional
    field — see each field's validator below for what "filled with valid
    information" means for it (non-blank after stripping whitespace, not
    just non-null).

    There is deliberately no provider_id: customers book a *service*, and
    the server assigns a suitable provider itself (see bookings.py).
    """

    # Which service is being booked. Must be one of SERVICE_CATEGORIES —
    # it's what the server matches a provider on, and what the booking's
    # rating is later attributed to.
    service_category: str = Field(min_length=1, max_length=100)
    # Which specific job under that category is being booked (e.g. "Fan
    # Installation" under "Electrical"). Optional, because a category with
    # no jobs listed for it books straight through at category level.
    #
    # Note there is deliberately no `price` field: the client displays the
    # price but never sends it. The server looks the job's price up in the
    # catalogue itself (app.constants.SERVICE_JOBS), so a customer can't
    # book a Rs. 3,500 termite treatment for Rs. 5 by editing the request.
    job_title: str | None = Field(default=None, max_length=150)
    address: str = Field(min_length=3, max_length=500)
    # Required, not optional: the client always sends these together with
    # the address (they come from the same map picker), so a booking with
    # an address but no coordinates means a broken/incomplete request,
    # not a legitimate one.
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    # Required: the customer must commit to a specific date and time up
    # front rather than leaving the provider to guess. No default — a
    # missing value is a 422, not a booking with no schedule.
    preferred_date: datetime
    # Required: a booking must say what the problem actually is. min_length
    # here only rejects the empty string outright; the real "is this
    # meaningful" check (whitespace-only, too short to be useful) happens
    # in the validator below, same pattern as `address`.
    problem_description: str = Field(min_length=1, max_length=1000)
    # The only optional field — anything extra the customer wants to add
    # on top of the required problem description.
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("service_category")
    @classmethod
    def service_category_must_be_known(cls, v: str) -> str:
        v = v.strip()
        if v not in SERVICE_CATEGORIES:
            raise ValueError("Please choose a valid service.")
        return v

    @field_validator("address")
    @classmethod
    def address_must_not_be_blank(cls, v: str) -> str:
        # min_length alone would let "   " (whitespace only) through.
        v = v.strip()
        if len(v) < 3:
            raise ValueError("Address is required.")
        return v

    @field_validator("problem_description")
    @classmethod
    def problem_description_must_be_meaningful(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 10:
            raise ValueError("Please describe the problem in at least 10 characters.")
        return v

    @field_validator("job_title")
    @classmethod
    def normalize_job_title(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @model_validator(mode="after")
    def job_must_belong_to_service(self) -> "BookingCreateRequest":
        # Needs both fields, hence a model validator rather than a field one.
        # Rejecting an unknown job outright (instead of quietly dropping it)
        # keeps a booking from being created with no price when the client
        # and server catalogues have drifted apart — better a clear error
        # than a silently unpriced job.
        if self.job_title is None:
            return self
        job = find_service_job(self.service_category, self.job_title)
        if job is None:
            raise ValueError(
                f"'{self.job_title}' is not a job offered under {self.service_category}."
            )
        # Store the catalogue's own spelling, so every booking of the same
        # job groups together regardless of how the client cased it.
        object.__setattr__(self, "job_title", job.name)
        return self


class BookingStatusUpdateRequest(BaseModel):
    status: BookingStatus


class BookingLocationUpdateRequest(BaseModel):
    """
    A single live-location sample the provider's device pushes while en
    route. Sent frequently (every few seconds) while the booking is
    'on_the_way' / 'arrived', so this is deliberately the smallest
    possible payload rather than the full booking.
    """

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class BookingOut(BaseModel):
    id: uuid.UUID
    customer_id: uuid.UUID
    customer_name: str
    customer_phone: str | None
    service_category: str | None
    # The specific job booked and what it was priced at. All three are None
    # for a category-level booking, and for any booking made before service
    # pricing existed. price_label is derived, not stored — it's the
    # display string for price + price_type (e.g. "From Rs. 2,500").
    job_title: str | None = None
    price: float | None = None
    price_type: PriceType | None = None
    price_label: str | None = None
    address: str
    latitude: float | None
    longitude: float | None
    # Optional here (unlike on BookingCreateRequest) purely for backward
    # compatibility with any booking row that predates this field.
    problem_description: str | None
    notes: str | None
    preferred_date: datetime | None
    status: BookingStatus
    created_at: datetime
    updated_at: datetime

    # The provider's live position while navigating to the customer.
    # Present only while status is 'on_the_way' / 'arrived'; null before
    # the provider sets out and again once the job reaches a terminal
    # status (see update_booking_status / update_booking_location in
    # routers/bookings.py, which set and clear these together).
    provider_latitude: float | None = None
    provider_longitude: float | None = None
    provider_location_updated_at: datetime | None = None

    # Present only once the customer has rated this booking (a rating of
    # the overall service, not of a provider). Kept inline
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
    service_category: str | None
    stars: int
    comment: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ServiceRatingOut(BaseModel):
    """
    A service's overall rating: the average of every customer rating left
    on completed bookings of that service. rating is 0.0 and reviews_count
    is 0 for a service nobody has rated yet.
    """

    service_category: str
    rating: float
    reviews_count: int


class ServiceJobOut(BaseModel):
    """
    One specific, bookable job under a service category, with its price.

    price_label is what the app actually renders ("Rs. 500", or
    "From Rs. 2,500" for starting-from pricing); price and price_type are
    sent alongside it so the client can sort, filter, or format differently
    without having to parse the label back apart.
    """

    name: str
    description: str
    price: float
    price_type: PriceType
    price_label: str


class ServiceCatalogEntryOut(BaseModel):
    """A service category with its priced jobs and its overall rating."""

    service_category: str
    rating: float
    reviews_count: int
    jobs: list[ServiceJobOut]