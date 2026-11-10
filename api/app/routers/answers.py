import uuid

from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.dependencies import ClockDep, RepoDep
from app.errors import ERROR_RESPONSES
from app.schemas.answers import SubmitAnswerRequest, SubmitAnswerResponse
from app.services import learning

router = APIRouter(prefix="/v1", tags=["answers"], responses=ERROR_RESPONSES)


@router.post("/answers", response_model=SubmitAnswerResponse)
def submit_answer(
    body: SubmitAnswerRequest, user: CurrentUserDep, repo: RepoDep, clock: ClockDep
) -> SubmitAnswerResponse:
    """Grade an answer to a choice / order / fill_blank / hallucination exercise.

    Every submission is recorded. XP is awarded for the first correct attempt per exercise.
    """
    return learning.submit_answer(repo, user.uid, body, now=clock(), attempt_id=uuid.uuid4().hex)
