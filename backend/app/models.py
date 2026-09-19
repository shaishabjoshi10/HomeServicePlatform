import enum
import uuid

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID

from app.constants import DEFAULT_CITY
from app.database import Base


class UserRole(str, enum.Enum):
    customer = "customer"
    provider = "provider"


class VerificationStatus(str, enum.Enum):
    pending = "pending"
    verified = "verified"
    rejected = "rejected"


class BookingStatus(str, enum.Enum):
    pending = "pending"          # created by customer, awaiting provider response
    accepted = "accepted"        # provider accepted
    rejected = "rejected"        # provider declined
    on_the_way = "on_the_way"    # provider has set out for the job
    arrived = "arrived"          # provider has reached the address
    completed = "completed"      # provider marked the job done
    cancelled = "cancelled"      # customer cancelled (only while still pending)


class User(Base):
    """
    A single person can hold both a 'customer' account and a 'provider'
    account with the same email/phone — that's why uniqueness is scoped
    to (identifier, role) rather than to the identifier alone.
    """

    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("email", "role", name="uq_users_email_role"),
        UniqueConstraint("phone", "role", name="uq_users_phone_role"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=True, index=True)
    phone = Column(String(20), nullable=True, index=True)
    password_hash = Column(String(255), nullable=False)
    role = Column(Enum(UserRole, name="user_role"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class CustomerProfile(Base):
    __tablename__ = "customer_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )
    name = Column(String(255), nullable=False)
    address = Column(String(500), nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)

    # Served URL path (e.g. "/uploads/profile_pictures/<file>"), not a raw
    # filesystem path — mirrors the citizenship_*_url convention below.
    profile_picture_url = Column(String(500), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ProviderProfile(Base):
    __tablename__ = "provider_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )
    name = Column(String(255), nullable=False)
    service_category = Column(String(100), nullable=True, index=True)
    experience = Column(String(50), nullable=True)  # a range label, e.g. "1-3 years"
    bio = Column(Text, nullable=True)

    # Served URL path (e.g. "/uploads/profile_pictures/<file>"), not a raw
    # filesystem path — same convention as citizenship_*_url below.
    profile_picture_url = Column(String(500), nullable=True)

    # Personal info, filled in via the "Complete your profile" flow. The
    # app currently only serves Kathmandu, so city is a fixed default
    # rather than a field the provider picks — see app.constants.DEFAULT_CITY.
    date_of_birth = Column(Date, nullable=True)
    city = Column(String(100), nullable=False, default=DEFAULT_CITY, server_default=DEFAULT_CITY)
    citizenship_number = Column(String(50), nullable=True)

    # Verification documents — store the served URL path (e.g.
    # "/uploads/citizenship/<file>"), not a raw filesystem path.
    citizenship_front_url = Column(String(500), nullable=True)
    citizenship_back_url = Column(String(500), nullable=True)

    # A contact email/phone for the profile itself — separate from the
    # login identifier on User, since that may be a phone number.
    alternative_email = Column(String(255), nullable=True)
    alternative_phone = Column(String(20), nullable=True)

    verification_status = Column(
        Enum(VerificationStatus, name="verification_status"),
        nullable=False,
        default=VerificationStatus.pending,
    )
    availability = Column(Boolean, nullable=False, default=True)

    # Note: providers deliberately carry no rating of their own. Customers
    # rate the overall *service* (see `Rating` below), not the individual
    # person who happened to do the job.

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    customer_id = Column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    provider_id = Column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    service_category = Column(String(100), nullable=True)
    # The specific job booked under that category (e.g. "Fan Installation"
    # under "Electrical"), plus the price it was booked at. Nullable for
    # backward compatibility with bookings made before jobs had prices, and
    # because a category with no listed jobs still books straight through.
    job_title = Column(String(150), nullable=True, index=True)
    # A *snapshot* of the catalogue price at the moment of booking, not a
    # live lookup: if the price of a job is changed in app.constants later,
    # bookings already placed keep the figure the customer actually agreed
    # to. Set server-side from the catalogue — never from the client.
    price = Column(Numeric(10, 2), nullable=True)
    # PriceType.value — "fixed" or "starting_from". Stored as a plain string
    # rather than a Postgres enum deliberately: adding a new pricing mode
    # then needs no ALTER TYPE migration on an existing database, unlike
    # booking_status (see the startup helper in main.py). The allowed values
    # are enforced by the API layer (schemas.py).
    price_type = Column(String(20), nullable=True)
    address = Column(String(500), nullable=False)
    # NOT NULL to match BookingCreateRequest, where these are required
    # (not Optional) fields — see the comment there. Without this, the DB
    # would silently accept a booking row with no coordinates if it were
    # ever inserted by anything other than the validated API path (a
    # script, a migration, a future endpoint), even though the API itself
    # never allows that.
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    # NOT NULL to match BookingCreateRequest: both are now mandatory at
    # booking time (see schemas.BookingCreateRequest). NOTE: create_all()
    # only creates missing tables, it does not add columns to a table that
    # already exists — a pre-existing "bookings" table needs a manual
    # `ALTER TABLE bookings ADD COLUMN problem_description ...` migration
    # (and to backfill preferred_date) before this model matches it.
    problem_description = Column(Text, nullable=False)
    preferred_date = Column(DateTime(timezone=True), nullable=False)
    notes = Column(Text, nullable=True)
    status = Column(
        Enum(BookingStatus, name="booking_status"),
        nullable=False,
        default=BookingStatus.pending,
        index=True,
    )
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Rating(Base):
    """
    A customer's rating of the overall service for one completed booking.
    It is a rating of the service (e.g. "Plumbing"), not of whichever
    provider was assigned to the job. Exactly one rating per booking —
    enforced both at the DB level (unique constraint on booking_id, so it
    holds even under concurrent requests) and by the route (which also
    checks the booking is 'completed' and belongs to the requesting
    customer before allowing it).

    service_category is copied from the booking when the rating is
    created, purely so a service's overall rating can be aggregated with a
    single GROUP BY on this table alone. There is intentionally no
    provider_id here.
    """

    __tablename__ = "ratings"
    __table_args__ = (
        UniqueConstraint("booking_id", name="uq_ratings_booking_id"),
        CheckConstraint("stars >= 1 AND stars <= 5", name="ck_ratings_stars_range"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    booking_id = Column(
        UUID(as_uuid=True), ForeignKey("bookings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    customer_id = Column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    service_category = Column(String(100), nullable=True, index=True)
    stars = Column(Integer, nullable=False)
    comment = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())