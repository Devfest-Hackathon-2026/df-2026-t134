import uuid

from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.dependencies import ClockDep, GeneratorDep, RepoDep
from app.errors import ERROR_RESPONSES
from app.schemas.prompt import EvaluatePromptRequest, EvaluatePromptResponse
from app.services import prompt_evaluation

router = APIRouter(prefix="/v1/prompt", tags=["prompt"], responses=ERROR_RESPONSES)


@router.post("/evaluate", response_model=EvaluatePromptResponse)
def evaluate_prompt(
    body: EvaluatePromptRequest,
    user: CurrentUserDep,
    repo: RepoDep,
    generator: GeneratorDep,
    clock: ClockDep,
) -> EvaluatePromptResponse:
    """Grade a learner's prompt with the rubric, or block it when it contains personal info."""
    return prompt_evaluation.evaluate_prompt(
        repo, generator, user.uid, body, now=clock(), attempt_id=uuid.uuid4().hex
    )
