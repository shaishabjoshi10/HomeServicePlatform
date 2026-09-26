from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Admin, User
from app.security import decode_access_token

bearer_scheme = HTTPBearer()

_INVALID_SESSION_DETAIL = "Invalid or expired session. Please log in again."


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials

    try:
        payload = decode_access_token(token)
        user_id = payload.get("sub")
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session. Please log in again.",
        )

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session. Please log in again.",
        )

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session. Please log in again.",
        )

    return user


def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> Admin:
    """
    Same shape as get_current_user, but resolves against the separate
    `admins` table and additionally requires the token's `role` claim to
    be 'admin'. That second check is what actually keeps a customer/
    provider token from ever reaching an admin-only route: their tokens
    carry role='customer'/'provider', and an admin's id living in a
    different table entirely means even a forged/reused id can't collide.
    """
    token = credentials.credentials

    try:
        payload = decode_access_token(token)
        admin_id = payload.get("sub")
        role = payload.get("role")
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_INVALID_SESSION_DETAIL)

    if not admin_id or role != "admin":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_INVALID_SESSION_DETAIL)

    admin = db.query(Admin).filter(Admin.id == admin_id).first()
    if not admin:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=_INVALID_SESSION_DETAIL)

    return admin