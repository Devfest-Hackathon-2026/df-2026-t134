from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.dependencies import ClockDep, RepoDep
from app.errors import ERROR_RESPONSES
from app.schemas.common import ErrorResponse, Id
from app.schemas.lessons import CompleteLessonResponse
from app.services import learning

router = APIRouter(
    prefix="/v1/lessons",
    tags=["lessons"],
    responses={**ERROR_RESPONSES, 409: {"model": ErrorResponse}},
)


@router.post("/{lesson_id}/complete", response_model=CompleteLessonResponse)
def complete_lesson(
    lesson_id: Id, user: CurrentUserDep, repo: RepoDep, clock: ClockDep
) -> CompleteLessonResponse:
    """Mark a lesson as completed once every exercise in it has an attempt (409 otherwise).

    Awards completion XP the first time and updates the streak (Asia/Tokyo calendar days).
    """
    return learning.complete_lesson(repo, user.uid, lesson_id, now=clock())
