import logging
import os

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.database import Base, engine
from app.routers import auth, bookings, profile, providers

logger = logging.getLogger("uvicorn.error")

# Creates tables if they don't exist yet. For a production app, switch to
# Alembic migrations instead of relying on create_all().
Base.metadata.create_all(bind=engine)

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