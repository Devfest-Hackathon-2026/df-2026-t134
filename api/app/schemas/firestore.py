"""Firestore documents.

| Collection                       | Model             | Written by     | Read by   |
|----------------------------------|-------------------|----------------|-----------|
| users/{uid}                      | UserProfile       | the user       | the user  |
| progress/{uid}                   | Progress          | server         | the user  |
| units/{unitId}                   | content.Unit      | tools          | signed-in |
| lessons/{lessonId}               | content.Lesson    | tools          | signed-in |
| exercises/{exerciseId}           | content.Exercise  | tools          | signed-in |
| answerKeys/{exerciseId}          | content.AnswerKey | tools          | server    |
| exerciseDrafts/{draftId}         | (PR-10)           | server / tools | server    |
| attempts/{uid}/items/{attemptId} | Attempt           | server         | the user  |
| liveChecks/{uid}/items/{session} | LiveCheckSession  | server         | server    |

Keep firebase/firestore.rules in sync with this table.
"""

import datetime as dt
from typing import Annotated, Self

from pydantic import AwareDatetime, Field, StringConstraints, model_validator

from app.schemas.common import Contract, ExerciseType, Grade, Id
from app.schemas.content import HallucinationError, Sentence
from app.schemas.live_check import WebSource

# Collection names of the table above (the single place that spells them).
USERS_COLLECTION = "users"
PROGRESS_COLLECTION = "progress"
UNITS_COLLECTION = "units"
LESSONS_COLLECTION = "lessons"
EXERCISES_COLLECTION = "exercises"
ANSWER_KEYS_COLLECTION = "answerKeys"
EXERCISE_DRAFTS_COLLECTION = "exerciseDrafts"
# attempts/{uid}/items/{attemptId}
ATTEMPTS_COLLECTION = "attempts"
ATTEMPT_ITEMS_SUBCOLLECTION = "items"
# liveChecks/{uid}/items/{sessionId}
LIVE_CHECKS_COLLECTION = "liveChecks"
LIVE_CHECK_ITEMS_SUBCOLLECTION = "items"

DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=20)]


class UserProfile(Contract):
    """Nickname only; real names and emails are not stored here."""

    display_name: DisplayName
    grade: Grade
    created_at: AwareDatetime


class Progress(Contract):
    xp: int = Field(ge=0)
    streak_days: int = Field(ge=0)
    # Calendar day in Asia/Tokyo of the last study session.
    last_studied_on: dt.date | None
    freeze_tickets: int = Field(ge=0, le=3)
    completed_lesson_ids: list[Id]


class Attempt(Contract):
    exercise_id: Id
    lesson_id: Id
    type: ExerciseType
    # None for AI-graded exercises (prompt), which use score instead.
    correct: bool | None
    score: int | None = Field(ge=0, le=10)
    # The submitted answer as sent by the app (prompt text for Q4).
    answer: dict[str, object]
    feedback_text: str
    xp_gained: int = Field(ge=0)
    created_at: AwareDatetime

    @model_validator(mode="after")
    def _grading_matches_type(self) -> Self:
        if self.type == "prompt":
            if self.correct is not None or self.score is None:
                raise ValueError("prompt attempts have a score and no correct flag")
        elif self.correct is None or self.score is not None:
            raise ValueError("non-prompt attempts have a correct flag and no score")
        return self


class LiveCheckSession(Contract):
    """One generated answer of a live_check exercise, with its secret answer key.
    Server only: clients never read it (the errors would give the answer away)."""

    exercise_id: Id
    lesson_id: Id
    # The learner's prompt is kept for teachers and safety review, like Attempt.answer.
    prompt: str
    sentences: list[Sentence] = Field(min_length=2, max_length=12)
    errors: list[HallucinationError] = Field(min_length=1, max_length=2)
    # Sources per sentence index (as a string key, Firestore map keys are strings).
    sources: dict[str, list[WebSource]]
    lookups_used: int = Field(ge=0)
    answered: bool
    created_at: AwareDatetime

    @model_validator(mode="after")
    def _errors_point_at_sentences(self) -> Self:
        if any(error.index >= len(self.sentences) for error in self.errors):
            raise ValueError("error indexes must point at sentences")
        if any(int(key) >= len(self.sentences) for key in self.sources):
            raise ValueError("source keys must be sentence indexes")
        return self
