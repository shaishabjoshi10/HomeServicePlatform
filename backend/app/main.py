import logging
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import inspect, text

from app.config import settings
from app.database import Base, engine
from app.models import BookingStatus
from app.routers import auth, bookings, profile, providers, services

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


def _migrate_to_service_level_ratings() -> None:
    """
    Brings an already-existing Postgres database in line with the
    service-level rating model. create_all() above only creates missing
    tables — it never alters existing ones — so without this a database
    created before the change would reject new ratings and new provider
    profiles with a raw DB error.

    What it does (each step is skipped when it isn't needed, so this is a
    no-op on a database that's already current or was just created fresh):
      * ratings: adds `service_category` (backfilled from each rating's
        booking) and relaxes NOT NULL on the old `provider_id`, which the
        model no longer writes.
      * provider_profiles: relaxes NOT NULL on the old `rating` and
        `reviews_count`, which the model no longer writes.

    It deliberately does not DROP the now-unused columns, so no data is
    lost; once you're happy with the change they can be removed by hand:
        ALTER TABLE ratings DROP COLUMN provider_id;
        ALTER TABLE provider_profiles DROP COLUMN rating, DROP COLUMN reviews_count;
    """
    if engine.dialect.name != "postgresql":
        return  # this project only targets Postgres in practice (see the enum helper above)

    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    with engine.begin() as conn:
        if "ratings" in tables:
            rating_columns = {c["name"] for c in inspector.get_columns("ratings")}
            if "service_category" not in rating_columns:
                conn.execute(text("ALTER TABLE ratings ADD COLUMN service_category VARCHAR(100)"))
                conn.execute(
                    text(
                        "UPDATE ratings SET service_category = bookings.service_category "
                        "FROM bookings WHERE ratings.booking_id = bookings.id"
                    )
                )
                conn.execute(
                    text("CREATE INDEX IF NOT EXISTS ix_ratings_service_category ON ratings (service_category)")
                )
            if "provider_id" in rating_columns:
                conn.execute(text("ALTER TABLE ratings ALTER COLUMN provider_id DROP NOT NULL"))

        if "provider_profiles" in tables:
            profile_columns = {c["name"] for c in inspector.get_columns("provider_profiles")}
            # Column names come from this fixed tuple, never from input.
            for column in ("rating", "reviews_count"):
                if column in profile_columns:
                    conn.execute(text(f"ALTER TABLE provider_profiles ALTER COLUMN {column} DROP NOT NULL"))


_migrate_to_service_level_ratings()


def _migrate_booking_pricing() -> None:
    """
    Adds the per-job pricing columns to an existing 'bookings' table.

    Same reason as the helpers above: create_all() only creates missing
    tables, it never adds columns to a table that already exists, so a
    database created before service pricing would reject every new booking
    with a raw DB error. All three columns are nullable, so existing rows
    simply keep no job or price — which is exactly how the app renders a
    booking made before jobs were priced.

    price_type is a plain VARCHAR rather than a Postgres enum on purpose:
    adding a future pricing mode then needs no ALTER TYPE dance (compare
    _ensure_booking_status_enum_values above). Its allowed values are
    enforced by the API layer.

    A no-op on a database that's already current or was just created fresh.
    """
    if engine.dialect.name != "postgresql":
        return

    inspector = inspect(engine)
    if "bookings" not in set(inspector.get_table_names()):
        return

    columns = {c["name"] for c in inspector.get_columns("bookings")}
    with engine.begin() as conn:
        if "job_title" not in columns:
            conn.execute(text("ALTER TABLE bookings ADD COLUMN job_title VARCHAR(150)"))
            conn.execute(
                text("CREATE INDEX IF NOT EXISTS ix_bookings_job_title ON bookings (job_title)")
            )
        if "price" not in columns:
            conn.execute(text("ALTER TABLE bookings ADD COLUMN price NUMERIC(10, 2)"))
        if "price_type" not in columns:
            conn.execute(text("ALTER TABLE bookings ADD COLUMN price_type VARCHAR(20)"))


_migrate_booking_pricing()

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
app.include_router(services.router)
app.include_router(bookings.router)


@app.get("/health")
def health():
    return {"status": "ok"}