import logging
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.database import Base, SessionLocal, engine
from sqlalchemy import text
from app.models import Admin
from app.routers import admin, auth, bookings, notifications, profile, providers, services
from app.security import hash_password


logger = logging.getLogger("uvicorn.error")

Base.metadata.create_all(bind=engine)


def _seed_default_admin() -> None:
    db = SessionLocal()

    try:
        email = settings.admin_email.strip().lower()

        existing = db.query(Admin).filter(Admin.email == email).first()

        if existing:
            return

        db.add(
            Admin(
                email=email,
                password_hash=hash_password(settings.admin_password),
            )
        )

        db.commit()

    finally:
        db.close()


_seed_default_admin()


def _ensure_payment_columns() -> None:
    """Small idempotent migration for existing PostgreSQL installations."""
    statements = [
        "ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION",
        "ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION",
        "ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS extra_charges NUMERIC(10,2) NOT NULL DEFAULT 0",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS extra_charge_note VARCHAR(500)",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_status VARCHAR(20) NOT NULL DEFAULT 'unpaid'",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_transaction_uuid VARCHAR(100)",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_reference VARCHAR(100)",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_updated_at TIMESTAMPTZ",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS payment_method VARCHAR(20)",
        "UPDATE bookings SET payment_method = 'esewa' WHERE payment_status = 'paid' AND payment_method IS NULL",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS customer_latitude DOUBLE PRECISION",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS customer_longitude DOUBLE PRECISION",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS customer_location_updated_at TIMESTAMPTZ",
        "ALTER TABLE bookings ADD COLUMN IF NOT EXISTS is_emergency BOOLEAN NOT NULL DEFAULT false",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_bookings_payment_transaction_uuid ON bookings(payment_transaction_uuid) WHERE payment_transaction_uuid IS NOT NULL",
    ]
    # Older databases may have a payment_attempts table created by an earlier
    # version of the model. create_all() never alters existing tables, so add
    # any columns the current model expects.
    statements += [
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS amount NUMERIC(10,2) NOT NULL DEFAULT 0",
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'pending'",
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS reference VARCHAR(100)",
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS raw_response TEXT",
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now()",
        "ALTER TABLE payment_attempts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now()",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_attempts_transaction_uuid ON payment_attempts(transaction_uuid)",
    ]
    # One statement per transaction so a single failure is logged, not fatal.
    for statement in statements:
        try:
            with engine.begin() as connection:
                connection.execute(text(statement))
        except Exception:
            logger.exception("Payment migration failed: %s", statement)


_ensure_payment_columns()


app = FastAPI(title="GharSewa API")


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


os.makedirs(settings.upload_dir, exist_ok=True)

app.mount(
    "/uploads",
    StaticFiles(directory=settings.upload_dir),
    name="uploads",
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(
    request: Request,
    exc: Exception,
):
    logger.exception(
        "Unhandled error on %s %s",
        request.method,
        request.url.path,
    )

    return JSONResponse(
        status_code=500,
        content={
            "detail": "Something went wrong on the server. Please try again."
        },
    )


app.include_router(auth.router)
app.include_router(profile.router)
app.include_router(providers.router)
app.include_router(services.router)
app.include_router(bookings.router)
app.include_router(notifications.router)
app.include_router(admin.router)


@app.get("/health")
def health():
    return {"status": "ok"}