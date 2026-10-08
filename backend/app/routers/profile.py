import os
from datetime import datetime, timezone
import uuid as uuid_module

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.config import settings
from app.constants import DEFAULT_CITY, EMERGENCY_SERVICE_CATEGORIES, EXPERIENCE_RANGES, SERVICE_CATEGORIES
from app.database import get_db
from app.deps import get_current_user
from app.models import CustomerProfile, ProviderProfile, User, UserRole, VerificationStatus
from app.schemas import (
    CustomerProfileOut,
    ProfileOptionsOut,
    ProfileUpdateRequest,
    ProviderAvailabilityUpdateRequest,
    ProviderLocationUpdateRequest,
    ProviderProfileOut,
)

router = APIRouter(prefix="/api/profile", tags=["profile"])

# Accepted formats: JPG, JPEG, PNG. "image/jpg" is not an official MIME type,
# but some browsers/clients send it for .jpg files, so it's accepted too.
_ALLOWED_IMAGE_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png"}
_ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
_UPLOAD_ERROR_DETAIL = "Allowed formats: JPG, JPEG, PNG. Maximum size: 5 MB per file."


def _save_uploaded_image(
    user_id: uuid_module.UUID,
    subdir: str,
    tag: str,
    upload: UploadFile,
) -> str:
    """
    Shared validate-and-save logic for any user-uploaded image (citizenship
    documents, profile pictures, ...). Saves under
    ``{settings.upload_dir}/{subdir}/`` and returns the served URL path.
    """
    ext = os.path.splitext(upload.filename or "")[1].lower()
    content_type = (upload.content_type or "").lower()

    # Some clients (older browsers, some HTTP libraries) either mislabel the
    # multipart Content-Type (e.g. "image/jpg" instead of "image/jpeg") or
    # don't set one at all (falling back to "application/octet-stream").
    # That was causing legitimate .jpg uploads to be rejected outright, so a
    # valid file extension is also accepted as proof of format even when the
    # content type doesn't match.
    if content_type not in _ALLOWED_IMAGE_CONTENT_TYPES and ext not in _ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=_UPLOAD_ERROR_DETAIL)

    contents = upload.file.read()
    max_bytes = settings.max_upload_mb * 1024 * 1024
    if len(contents) > max_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=_UPLOAD_ERROR_DETAIL)
    if len(contents) == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded file is empty.")

    ext = ext or ".jpg"
    filename = f"{user_id}_{tag}_{uuid_module.uuid4().hex[:8]}{ext}"
    directory = os.path.join(settings.upload_dir, subdir)
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, filename), "wb") as f:
        f.write(contents)

    return f"/uploads/{subdir}/{filename}"


def _save_citizenship_image(user_id: uuid_module.UUID, side: str, upload: UploadFile) -> str:
    return _save_uploaded_image(user_id, "citizenship", side, upload)


def _save_profile_picture(user_id: uuid_module.UUID, upload: UploadFile) -> str:
    return _save_uploaded_image(user_id, "profile_pictures", "avatar", upload)


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
        experience_ranges=EXPERIENCE_RANGES,
        default_city=DEFAULT_CITY,
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
        # `availability` defaults to true, and for Electrical/Plumbing that
        # switch also starts live location sharing. A provider who has never
        # shared a location must opt in via the switch, not get tracked just
        # because they picked this category.
        if (
            payload.service_category in EMERGENCY_SERVICE_CATEGORIES
            and profile.service_category != payload.service_category
            and profile.location_updated_at is None
        ):
            profile.availability = False
        profile.service_category = payload.service_category
    if payload.experience is not None:
        profile.experience = payload.experience
    if payload.bio is not None:
        profile.bio = payload.bio
    if payload.availability is not None:
        # Switching an emergency provider ON must go through
        # PUT /me/availability so the flag and a GPS position are saved
        # together; otherwise they would look "available" but never be found.
        if (
            payload.availability
            and profile.service_category in EMERGENCY_SERVICE_CATEGORIES
            and (profile.latitude is None or profile.location_updated_at is None)
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Use the availability switch on the home screen to go available - it needs your current location.",
            )
        profile.availability = payload.availability
    if payload.date_of_birth is not None:
        profile.date_of_birth = payload.date_of_birth
    if payload.citizenship_number is not None:
        profile.citizenship_number = payload.citizenship_number
    if payload.alternative_email is not None:
        profile.alternative_email = payload.alternative_email
    if payload.alternative_phone is not None:
        profile.alternative_phone = payload.alternative_phone

    db.commit()
    db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)


@router.put("/me/availability", response_model=ProviderProfileOut)
def update_provider_availability(
    payload: ProviderAvailabilityUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Switch emergency availability on or off.

    ON saves the availability flag and the provider's current GPS position in
    one transaction, so the provider shows up in customers' live emergency
    list right away (for their own category, near their current location).
    OFF removes them from that list right away.
    """
    if current_user.role != UserRole.provider:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only service provider accounts can change availability.",
        )

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).with_for_update().first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    if payload.availability:
        if profile.service_category not in EMERGENCY_SERVICE_CATEGORIES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Emergency service is only available for: {', '.join(EMERGENCY_SERVICE_CATEGORIES)}.",
            )
        if profile.verification_status != VerificationStatus.verified:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your profile must be verified by an admin before you can receive emergency requests.",
            )
        if payload.latitude is None or payload.longitude is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your current location is required to receive emergency requests.",
            )
        profile.latitude = payload.latitude
        profile.longitude = payload.longitude
        profile.location_updated_at = datetime.now(timezone.utc)
        profile.availability = True
    else:
        profile.availability = False
        # While unavailable the app stops reporting location, so don't leave
        # a stale position looking "live" on the record.
        profile.location_updated_at = None

    db.commit()
    db.refresh(profile)
    return ProviderProfileOut.model_validate(profile)


@router.put("/me/location", response_model=ProviderProfileOut)
def update_provider_location(
    payload: ProviderLocationUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Store the provider's latest device location for nearby emergency search."""
    if current_user.role != UserRole.provider:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only service provider accounts can update provider location.",
        )

    profile = db.query(ProviderProfile).filter(ProviderProfile.user_id == current_user.id).with_for_update().first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    # Only a provider who switched emergency availability ON shares a live
    # location. This also stops a late in-flight update from re-stamping a
    # location right after the provider switched OFF.
    if not profile.availability or profile.service_category not in EMERGENCY_SERVICE_CATEGORIES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Turn on emergency availability to share your location.",
        )

    profile.latitude = payload.latitude
    profile.longitude = payload.longitude
    profile.location_updated_at = datetime.now(timezone.utc)
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


def _get_own_profile(current_user: User, db: Session) -> CustomerProfile | ProviderProfile:
    model = CustomerProfile if current_user.role == UserRole.customer else ProviderProfile
    profile = db.query(model).filter(model.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")
    return profile


@router.post("/me/picture")
def upload_profile_picture(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Uploads/replaces the caller's own profile picture. Works for both
    customer and provider accounts — which table is updated depends on
    the caller's role, same pattern as GET/PUT /api/profile/me.
    """
    profile = _get_own_profile(current_user, db)

    new_url = _save_profile_picture(current_user.id, file)
    if profile.profile_picture_url:
        _delete_local_upload(profile.profile_picture_url)
    profile.profile_picture_url = new_url

    db.commit()
    db.refresh(profile)

    if current_user.role == UserRole.customer:
        return CustomerProfileOut.model_validate(profile)
    return ProviderProfileOut.model_validate(profile)


@router.delete("/me/picture")
def delete_profile_picture(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Removes the caller's profile picture, reverting to the placeholder icon."""
    profile = _get_own_profile(current_user, db)

    if profile.profile_picture_url:
        _delete_local_upload(profile.profile_picture_url)
        profile.profile_picture_url = None
        db.commit()
        db.refresh(profile)

    if current_user.role == UserRole.customer:
        return CustomerProfileOut.model_validate(profile)
    return ProviderProfileOut.model_validate(profile)