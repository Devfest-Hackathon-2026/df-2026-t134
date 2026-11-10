"""Live hallucination check (exercise type `live_check`).

1. POST /v1/live-checks: the learner sends their own prompt about the exercise's theme.
   The server writes a grounded answer (Google Search), secretly rewrites `errorCount`
   sentences to be wrong and returns the sentences (or `blocked` without calling the model).
2. POST /v1/live-checks/{sessionId}/lookup: the learner looks up the Google Search sources for
   one sentence, at most `lookupLimit` times per session.
3. POST /v1/answers with a `live_check` answer: graded against the session.
"""

from typing import Annotated, Literal

from pydantic import Field, StringConstraints

from app.schemas.common import Contract, Id
from app.schemas.content import Sentence
from app.schemas.prompt import BlockReason

LiveCheckPromptText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=400)
]


class WebSource(Contract):
    """A web page Google Search returned for the grounded answer."""

    title: str
    uri: str


class StartLiveCheckRequest(Contract):
    exercise_id: Id
    prompt: LiveCheckPromptText


class LiveCheckStarted(Contract):
    status: Literal["generated"]
    session_id: Id
    sentences: list[Sentence] = Field(min_length=2, max_length=12)
    error_count: int = Field(ge=1, le=2)
    lookups_left: int = Field(ge=0)


class LiveCheckBlocked(Contract):
    """The prompt was not sent to the model (personal info, inappropriate, off the theme).
    Nothing was recorded; the learner edits the prompt and tries again."""

    status: Literal["blocked"]
    reasons: list[BlockReason] = Field(min_length=1)
    message: str


StartLiveCheckResponse = Annotated[
    LiveCheckStarted | LiveCheckBlocked,
    Field(discriminator="status"),
]


class LookupRequest(Contract):
    sentence_index: int = Field(ge=0)


class LookupResponse(Contract):
    sentence_index: int
    sources: list[WebSource]
    lookups_left: int = Field(ge=0)
