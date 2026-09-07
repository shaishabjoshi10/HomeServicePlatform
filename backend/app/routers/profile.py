from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import CustomerProfile, ProviderProfile, User, UserRole
from app.schemas import CustomerProfileOut, ProfileUpdateRequest, ProviderProfileOut

router = APIRouter(prefix="/api/profile", tags=["profile"])


@router.get("/me")
def get_my_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role == UserRole.customer:
        profile = db.query(CustomerProfile).filter(CustomerProfile.user_id == current_user.id).first()
        if not profile:
            # Handles accounts created before profile auto-creation existed.
            profile = CustomerProfile(user_id=current_user.id, name=current_user.full_name)
            db.add(profile)
            db.commit()
            db.refresh(profile)
        return CustomerProfileOut.model_validate(profile)

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).first()
    if not profile:
        # Handles accounts created before profile auto-creation existed.
        profile = ProviderProfile(user_id=current_user.id, name=current_user.full_name)
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)


@router.put("/me")
def update_my_profile(
    payload: ProfileUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role == UserRole.customer:
        profile = db.query(CustomerProfile).filter(CustomerProfile.user_id == current_user.id).first()
        if not profile:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

        if payload.name is not None:
            profile.name = payload.name
        if payload.address is not None:
            profile.address = payload.address
        if payload.latitude is not None:
            profile.latitude = payload.latitude
        if payload.longitude is not None:
            profile.longitude = payload.longitude

        db.commit()
        db.refresh(profile)
        return CustomerProfileOut.model_validate(profile)

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    if payload.name is not None:
        profile.name = payload.name
    if payload.address is not None:
        profile.address = payload.address
    if payload.service_category is not None:
        profile.service_category = payload.service_category
    if payload.experience is not None:
        profile.experience = payload.experience
    if payload.availability is not None:
        profile.availability = payload.availability

    db.commit()
    db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)