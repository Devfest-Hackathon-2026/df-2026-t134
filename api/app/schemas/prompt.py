"""POST /v1/prompt/evaluate: grade a learner's prompt (Q4) with the shared rubric."""

from typing import Annotated, Literal

from pydantic import Field, StringConstraints

from app.schemas.common import Contract, Id, ProgressSnapshot

RubricScore = Annotated[int, Field(ge=0, le=2)]

PromptText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]

BlockReason = Literal["personal_info", "inappropriate", "off_topic"]


class EvaluatePromptRequest(Contract):
    exercise_id: Id
    prompt: PromptText


class RubricScores(Contract):
    purpose: RubricScore
    context: RubricScore
    constraints: RubricScore
    format: RubricScore
    safety: RubricScore


class PromptEvaluated(Contract):
    status: Literal["evaluated"]
    attempt_id: Id
    total: int = Field(ge=0, le=10)
    scores: RubricScores
    good_point: str
    improvements: list[str] = Field(min_length=1, max_length=2)
    hint: str
    progress: ProgressSnapshot


class PromptBlocked(Contract):
    """The prompt was not sent to the model, e.g. because it contains personal information.

    This is an expected outcome (a teaching moment), not an error.
    """

    status: Literal["blocked"]
    reasons: list[BlockReason] = Field(min_length=1)
    message: str


EvaluatePromptResponse = Annotated[
    PromptEvaluated | PromptBlocked,
    Field(discriminator="status"),
]
