import os
import uuid as uuid_module

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.config import settings
from app.constants import CITIES, CITY_MUNICIPALITIES, EXPERIENCE_RANGES, MARITAL_STATUS_OPTIONS, SERVICE_CATEGORIES
from app.database import get_db
from app.deps import get_current_user
from app.models import CustomerProfile, ProviderProfile, User, UserRole, VerificationStatus
from app.schemas import CustomerProfileOut, ProfileOptionsOut, ProfileUpdateRequest, ProviderProfileOut

router = APIRouter(prefix="/api/profile", tags=["profile"])

_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}


def _save_citizenship_image(user_id: uuid_module.UUID, side: str, upload: UploadFile) -> str:
    if upload.content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only JPEG, PNG, or WEBP images are allowed.",
        )

    contents = upload.file.read()
    max_bytes = settings.max_upload_mb * 1024 * 1024
    if len(contents) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File too large — max {settings.max_upload_mb}MB.",
        )

    ext = os.path.splitext(upload.filename or "")[1].lower() or ".jpg"
    filename = f"{user_id}_{side}_{uuid_module.uuid4().hex[:8]}{ext}"
    directory = os.path.join(settings.upload_dir, "citizenship")
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, filename), "wb") as f:
        f.write(contents)

    return f"/uploads/citizenship/{filename}"


def _delete_local_upload(url_path: str) -> None:
    relative = url_path.removeprefix("/uploads/")
    full_path = os.path.join(settings.upload_dir, relative)
    try:
        os.remove(full_path)
    except OSError:
        pass  # already gone, or never existed on this disk — safe to ignore


@router.get("/form-options", response_model=ProfileOptionsOut)
def get_profile_form_options():
    """Dropdown option lists for the provider verification form."""
    return ProfileOptionsOut(
        service_categories=SERVICE_CATEGORIES,
        cities=CITIES,
        municipalities_by_city=CITY_MUNICIPALITIES,
        experience_ranges=EXPERIENCE_RANGES,
        marital_statuses=MARITAL_STATUS_OPTIONS,
    )


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
    if payload.service_category is not None:
        profile.service_category = payload.service_category
    if payload.experience is not None:
        profile.experience = payload.experience
    if payload.bio is not None:
        profile.bio = payload.bio
    if payload.availability is not None:
        profile.availability = payload.availability
    if payload.marital_status is not None:
        profile.marital_status = payload.marital_status
    if payload.permanent_address is not None:
        profile.permanent_address = payload.permanent_address
    if payload.current_address is not None:
        profile.current_address = payload.current_address
    if payload.city is not None:
        profile.city = payload.city
    if payload.municipality is not None:
        profile.municipality = payload.municipality
    if payload.tole is not None:
        profile.tole = payload.tole
    if payload.ward_no is not None:
        profile.ward_no = payload.ward_no
    if payload.citizenship_number is not None:
        profile.citizenship_number = payload.citizenship_number
    if payload.alternative_email is not None:
        profile.alternative_email = payload.alternative_email
    if payload.alternative_phone is not None:
        profile.alternative_phone = payload.alternative_phone

    db.commit()
    db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)


@router.post("/me/documents/citizenship", response_model=ProviderProfileOut)
def upload_citizenship_documents(
    front: UploadFile | None = File(default=None),
    back: UploadFile | None = File(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role != UserRole.provider:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only service provider accounts can upload verification documents.",
        )
    if front is None and back is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Upload at least one of the front or back image.",
        )

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    if front is not None:
        new_front_url = _save_citizenship_image(current_user.id, "front", front)
        if profile.citizenship_front_url:
            _delete_local_upload(profile.citizenship_front_url)
        profile.citizenship_front_url = new_front_url

    if back is not None:
        new_back_url = _save_citizenship_image(current_user.id, "back", back)
        if profile.citizenship_back_url:
            _delete_local_upload(profile.citizenship_back_url)
        profile.citizenship_back_url = new_back_url

    # Re-uploading resets verification — an admin needs to review the new documents.
    profile.verification_status = VerificationStatus.pending

    db.commit()
    db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)