from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from pydantic.alias_generators import to_camel

# Lowercase kebab-case ids such as "u1", "u1-l2", "u1-l2-q3".
Id = Annotated[
    str,
    StringConstraints(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", min_length=1, max_length=64),
]

# Japanese school years: j1-j3 = junior high, h1-h3 = senior high.
Grade = Literal["j1", "j2", "j3", "h1", "h2", "h3"]

ExerciseType = Literal[
    "choice", "order", "fill_blank", "hallucination", "prompt", "story", "live_check", "agent"
]

NonEmptyText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class Contract(BaseModel):
    """Base for every contract model.

    JSON uses camelCase (exerciseId), Python uses snake_case (exercise_id).
    Unknown fields are rejected and instances are immutable.
    """

    model_config = ConfigDict(
        extra="forbid",
        frozen=True,
        alias_generator=to_camel,
        validate_by_name=True,
        validate_by_alias=True,
        serialize_by_alias=True,
    )


ErrorCode = Literal[
    "bad_request",
    "unauthenticated",
    "forbidden",
    "not_found",
    "conflict",
    "rate_limited",
    "not_implemented",
    "upstream_unavailable",
    "internal",
]


class ErrorBody(Contract):
    code: ErrorCode
    message: str


class ErrorResponse(Contract):
    """Body of every non-2xx response."""

    error: ErrorBody


class ProgressSnapshot(Contract):
    """Learner progress right after an action, returned so the app can update without a re-read."""

    xp: int = Field(ge=0)
    xp_gained: int = Field(ge=0)
    streak_days: int = Field(ge=0)
