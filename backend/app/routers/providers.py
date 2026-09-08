from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.constants import SERVICE_CATEGORIES
from app.database import get_db
from app.models import ProviderProfile, VerificationStatus
from app.schemas import ProviderPublicOut

router = APIRouter(prefix="/api/providers", tags=["providers"])


@router.get("/categories", response_model=list[str])
def list_service_categories():
    """Predefined categories shown in the signup dropdown. A custom value
    is still accepted at signup (e.g. via an 'Other' option) — this list
    is just for suggesting common ones."""
    return SERVICE_CATEGORIES


@router.get("", response_model=list[ProviderPublicOut])
def list_providers(
    service_category: str | None = Query(default=None, description="Filter by category, partial match"),
    available_only: bool = Query(default=False),
    verified_only: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    query = db.query(ProviderProfile)

    if service_category:
        query = query.filter(ProviderProfile.service_category.ilike(f"%{service_category}%"))
    if available_only:
        query = query.filter(ProviderProfile.availability.is_(True))
    if verified_only:
        query = query.filter(ProviderProfile.verification_status == VerificationStatus.verified)

    query = query.order_by(ProviderProfile.rating.desc()).limit(limit)
    return query.all()


@router.get("/{provider_id}", response_model=ProviderPublicOut)
def get_provider(provider_id: str, db: Session = Depends(get_db)):
    profile = db.query(ProviderProfile).filter(ProviderProfile.id == provider_id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider not found")
    return profile