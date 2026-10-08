import logging
import math
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, exists, func, or_
from sqlalchemy.orm import Session

from app.constants import EMERGENCY_SERVICE_CATEGORIES, SERVICE_CATEGORIES
from app.database import get_db
from app.deps import get_current_user
from app.models import Booking, BookingStatus, ProviderProfile, User, UserRole, VerificationStatus
from app.schemas import EmergencyProviderOut

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/providers", tags=["providers"])

# How recent a provider's last location report must be for them to count as
# "nearby right now". The provider app reports every 30 seconds while it is in
# the foreground, but mobile OSes pause timers when the screen locks or the app
# is backgrounded, so 10 minutes tolerates a short pocket/lock-screen gap while
# still hiding a provider whose app has really been closed. Shared with the
# emergency-booking route so the list and the booking check never disagree.
EMERGENCY_LOCATION_MAX_AGE = timedelta(minutes=10)

# A provider is "busy" (cannot take an emergency request) when:
#   * they are travelling to / working a job right now (on_the_way, arrived), or
#   * they accepted a scheduled job that starts within the next 2 hours, or
#     started within the last 3 hours and has not been moved on yet.
# An accepted job scheduled for tomorrow — or a stale accepted job nobody ever
# completed — must NOT hide the provider from emergency search; before this
# rule, any leftover "accepted" booking removed a provider for good.
_IN_PROGRESS_STATUSES = (BookingStatus.on_the_way, BookingStatus.arrived)
_ACCEPTED_BUSY_LEAD = timedelta(hours=2)
_ACCEPTED_BUSY_TAIL = timedelta(hours=3)


def _active_job_clause(now: datetime):
    """SQL condition on `Booking` meaning "this booking keeps its provider busy"."""
    return or_(
        Booking.status.in_(_IN_PROGRESS_STATUSES),
        # An accepted emergency job is "as soon as possible": its
        # preferred_date is the moment the request was CREATED, so the time
        # window below would stop covering it if the provider accepted a few
        # hours later, and a provider mid-job would reappear in the list.
        and_(
            Booking.status == BookingStatus.accepted,
            Booking.is_emergency.is_(True),
        ),
        and_(
            Booking.status == BookingStatus.accepted,
            Booking.preferred_date <= now + _ACCEPTED_BUSY_LEAD,
            Booking.preferred_date >= now - _ACCEPTED_BUSY_TAIL,
        ),
    )


def provider_has_active_job(db: Session, provider_id) -> bool:
    now = datetime.now(timezone.utc)
    return (
        db.query(Booking.id)
        .filter(Booking.provider_id == provider_id, _active_job_clause(now))
        .first()
        is not None
    )


# Only the category list lives here now (it feeds the provider signup
# dropdown). The emergency endpoint below is deliberately customer-only and
# exposes only verified, available providers within the requested radius.
@router.get("/categories", response_model=list[str])
def list_service_categories():
    return SERVICE_CATEGORIES


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance using the Haversine formula."""
    radius = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    # min() guards against a tiny floating-point overshoot above 1.0.
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1 - a)))


def _canonical_category(value: str) -> str | None:
    """Match a category ignoring case/whitespace, returning the canonical name."""
    wanted = value.strip().lower()
    for category in SERVICE_CATEGORIES:
        if category.lower() == wanted:
            return category
    return None


@router.get("/emergency/available", response_model=list[EmergencyProviderOut])
def find_available_emergency_providers(
    service_category: str = Query(..., min_length=1, max_length=100),
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(10.0, gt=0, le=50),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Find nearby providers who are verified and currently available."""
    if current_user.role != UserRole.customer:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only customer accounts can search for emergency providers.",
        )

    category = _canonical_category(service_category)
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown service category. Choose one of: {', '.join(SERVICE_CATEGORIES)}",
        )

    if category not in EMERGENCY_SERVICE_CATEGORIES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Emergency service is only available for: {', '.join(EMERGENCY_SERVICE_CATEGORIES)}.",
        )

    now = datetime.now(timezone.utc)

    # Category is compared case/whitespace-insensitively so a stored value like
    # "electrical " can never silently drop a provider out of the list.
    base = db.query(ProviderProfile).filter(
        func.lower(func.trim(ProviderProfile.service_category)) == category.lower(),
        ProviderProfile.verification_status == VerificationStatus.verified,
    )
    eligible = base.filter(
        ProviderProfile.availability.is_(True),
        ProviderProfile.latitude.isnot(None),
        ProviderProfile.longitude.isnot(None),
        ProviderProfile.location_updated_at.isnot(None),
        ProviderProfile.location_updated_at >= now - EMERGENCY_LOCATION_MAX_AGE,
        # NOT EXISTS rather than NOT IN (...): NOT IN returns no rows at all if
        # the subquery ever yields a NULL, which would hide every provider.
        ~exists().where(
            Booking.provider_id == ProviderProfile.user_id,
            _active_job_clause(now),
        ),
    )
    providers = eligible.all()

    results = []
    for provider in providers:
        distance = _distance_km(latitude, longitude, provider.latitude, provider.longitude)
        if distance <= radius_km:
            results.append(
                EmergencyProviderOut(
                    user_id=provider.user_id,
                    name=provider.name,
                    service_category=provider.service_category,
                    experience=provider.experience,
                    bio=provider.bio,
                    city=provider.city,
                    profile_picture_url=provider.profile_picture_url,
                    latitude=provider.latitude,
                    longitude=provider.longitude,
                    distance_km=round(distance, 2),
                )
            )

    # Set LOG level to DEBUG to see why providers drop out of the list.
    if logger.isEnabledFor(logging.DEBUG):
        verified_count = base.count()
        available_count = base.filter(ProviderProfile.availability.is_(True)).count()
        logger.debug(
            "emergency search category=%s at (%.5f, %.5f) r=%.1fkm: verified=%d available=%d "
            "eligible(live+free)=%d within_radius=%d",
            category, latitude, longitude, radius_km,
            verified_count, available_count, len(providers), len(results),
        )

    results.sort(key=lambda provider: provider.distance_km)
    return results