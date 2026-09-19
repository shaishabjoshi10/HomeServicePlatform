from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.constants import SERVICE_CATEGORIES, jobs_for_category
from app.database import get_db
from app.deps import get_current_user
from app.models import Rating
from app.schemas import ServiceCatalogEntryOut, ServiceJobOut, ServiceRatingOut

router = APIRouter(prefix="/api/services", tags=["services"])


def _rating_stats(db: Session) -> dict[str, tuple[float, int]]:
    """
    Average stars and review count per service, keyed by service category.

    Computed on read from the ratings table (one GROUP BY on the indexed
    Rating.service_category), so there is no cached figure that could drift
    out of sync with the ratings themselves.
    """
    rows = (
        db.query(Rating.service_category, func.avg(Rating.stars), func.count(Rating.id))
        .filter(Rating.service_category.isnot(None))
        .group_by(Rating.service_category)
        .all()
    )
    return {category: (float(avg), count) for category, avg, count in rows}


@router.get(
    "/ratings",
    response_model=list[ServiceRatingOut],
    dependencies=[Depends(get_current_user)],
)
def list_service_ratings(db: Session = Depends(get_db)):
    """
    Overall rating of every service, in SERVICE_CATEGORIES order. A service
    nobody has rated yet is still listed, with rating 0.0 and
    reviews_count 0.
    """
    stats = _rating_stats(db)

    result = []
    for category in SERVICE_CATEGORIES:
        avg, count = stats.get(category, (0.0, 0))
        result.append(
            ServiceRatingOut(
                service_category=category,
                rating=round(avg, 1),
                reviews_count=count,
            )
        )
    return result


@router.get(
    "/catalog",
    response_model=list[ServiceCatalogEntryOut],
    dependencies=[Depends(get_current_user)],
)
def list_service_catalog(db: Session = Depends(get_db)):
    """
    Every service with its bookable jobs, each job's price, and the
    service's overall rating — everything the home screen needs in one
    request instead of one per service.

    This is the authoritative price list. The app renders what it reads
    here, and a booking's price is looked up from the same catalogue
    server-side (see routers/bookings.py), so the two can never disagree
    about what a job costs even if an old build of the app is still
    showing a stale figure.
    """
    stats = _rating_stats(db)

    result = []
    for category in SERVICE_CATEGORIES:
        avg, count = stats.get(category, (0.0, 0))
        result.append(
            ServiceCatalogEntryOut(
                service_category=category,
                rating=round(avg, 1),
                reviews_count=count,
                jobs=[
                    ServiceJobOut(
                        name=job.name,
                        description=job.description,
                        price=float(job.price),
                        price_type=job.price_type,
                        price_label=job.price_label,
                    )
                    for job in jobs_for_category(category)
                ],
            )
        )
    return result