from fastapi import APIRouter

from app.constants import SERVICE_CATEGORIES

router = APIRouter(prefix="/api/providers", tags=["providers"])


# Only the category list lives here now (it feeds the provider signup
# dropdown). The endpoints that listed/looked up individual providers were
# removed on purpose: customers book a service and are assigned a provider
# by the server, so nothing should let a client browse providers.
@router.get("/categories", response_model=list[str])
def list_service_categories():
    return SERVICE_CATEGORIES