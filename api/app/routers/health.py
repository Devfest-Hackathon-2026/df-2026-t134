from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel

from app.config import AppEnv, Settings

router = APIRouter(prefix="/v1", tags=["health"])


class HealthResponse(BaseModel):
    status: Literal["ok"]
    version: str
    env: AppEnv


# Cloud Run reserves some paths ending in "z" (such as /healthz), so use /v1/health.
@router.get("/health", response_model=HealthResponse)
def get_health(request: Request) -> HealthResponse:
    settings: Settings = request.app.state.settings
    return HealthResponse(status="ok", version=request.app.version, env=settings.app_env)
