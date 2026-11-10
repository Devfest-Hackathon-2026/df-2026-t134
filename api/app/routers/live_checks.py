import time
import uuid

from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.dependencies import AnswererDep, ClockDep, GeneratorDep, RepoDep, SettingsDep
from app.errors import ERROR_RESPONSES
from app.schemas.common import Id
from app.schemas.live_check import (
    LookupRequest,
    LookupResponse,
    StartLiveCheckRequest,
    StartLiveCheckResponse,
)
from app.services import live_check

router = APIRouter(prefix="/v1/live-checks", tags=["live checks"], responses=ERROR_RESPONSES)


@router.post("", response_model=StartLiveCheckResponse)
def start_live_check(
    body: StartLiveCheckRequest,
    user: CurrentUserDep,
    repo: RepoDep,
    answerer: AnswererDep,
    generator: GeneratorDep,
    settings: SettingsDep,
    clock: ClockDep,
) -> StartLiveCheckResponse:
    """Answer the learner's prompt with a grounded answer that has secretly rewritten sentences,
    or block the prompt (personal info, inappropriate, off the theme) without calling the model.
    429 rate_limited after the daily limit, 503 upstream_unavailable when AI is off."""
    return live_check.start_live_check(
        repo,
        answerer,
        generator,
        user.uid,
        body,
        daily_limit=settings.live_check_daily_limit,
        now=clock(),
        session_id=uuid.uuid4().hex,
        elapsed=live_check.monotonic_since(time.monotonic()),
    )


@router.post("/{session_id}/lookup", response_model=LookupResponse)
def lookup_sources(
    session_id: Id, body: LookupRequest, user: CurrentUserDep, repo: RepoDep
) -> LookupResponse:
    """Google Search sources for one sentence of the caller's session.
    404 for another learner's session, 409 conflict when no lookups are left or it is answered."""
    return live_check.lookup_sources(repo, user.uid, session_id, body.sentence_index)
