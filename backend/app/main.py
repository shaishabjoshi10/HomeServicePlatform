import logging
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.config import settings
from app.database import Base, engine
from app.models import BookingStatus
from app.routers import auth, bookings, profile, providers

logger = logging.getLogger("uvicorn.error")

# Creates tables if they don't exist yet. For a production app, switch to
# Alembic migrations instead of relying on create_all().
Base.metadata.create_all(bind=engine)


def _ensure_booking_status_enum_values() -> None:
    """
    create_all() above only creates missing tables/types — it does NOT add
    new values to an already-existing Postgres enum type. Without this, a
    database whose 'booking_status' type was created before 'on_the_way'
    and 'arrived' existed rejects those values with a raw DB error, which
    the client only ever sees as a generic 500 ("Something went wrong on
    the server") with no indication of the real cause.

    This runs on every startup and adds any BookingStatus values Postgres
    doesn't have yet. IF NOT EXISTS makes it a no-op once the type is
    already current, and it's equally a no-op on a database create_all()
    just created from scratch (that type already has every value). Adding
    enum values can't run inside a transaction block, hence AUTOCOMMIT.
    """
    if engine.dialect.name != "postgresql":
        return  # ALTER TYPE ... ADD VALUE is Postgres-specific (e.g. skip for sqlite in tests)

    with engine.connect() as conn:
        conn = conn.execution_options(isolation_level="AUTOCOMMIT")
        for member in BookingStatus:
            # member.value comes from our own fixed enum, never external
            # input, so interpolating it directly is safe — ALTER TYPE
            # doesn't support a bind parameter for the value being added.
            conn.execute(text(f"ALTER TYPE booking_status ADD VALUE IF NOT EXISTS '{member.value}'"))


_ensure_booking_status_enum_values()

app = FastAPI(title="GharSewa API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serves uploaded verification documents (e.g. citizenship photos) at
# /uploads/... . For production, swap local disk + this mount for cloud
# storage (S3-compatible) and store full URLs instead.
os.makedirs(settings.upload_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Without this, an unhandled error (e.g. a DB or hashing library issue)
    # returns plain text, which breaks any client trying to json-decode it.
    # The full traceback still goes to the uvicorn console for debugging.
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Something went wrong on the server. Please try again."},
    )


app.include_router(auth.router)
app.include_router(profile.router)
app.include_router(providers.router)
app.include_router(bookings.router)


@app.get("/health")
def health():
    return {"status": "ok"}