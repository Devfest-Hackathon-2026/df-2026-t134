"""Helpers for the emulator suite: a fake verifier and answers built from the seeded keys."""

from typing import Any

from app.auth import CurrentUser
from app.schemas.content import (
    AnswerKey,
    ChoiceAnswerKey,
    ChoiceExercise,
    Exercise,
    FillBlankAnswerKey,
    FillBlankExercise,
    HallucinationAnswerKey,
    OrderAnswerKey,
)

# Seeded from content/units/u1 by the make target.
SEEDED_LESSON_ID = "u1-l1"


def correct_answer(key: AnswerKey) -> dict[str, Any]:
    match key:
        case ChoiceAnswerKey():
            return {"type": "choice", "optionId": key.correct_option_id}
        case OrderAnswerKey():
            return {"type": "order", "itemIds": key.correct_order}
        case FillBlankAnswerKey():
            return {"type": "fill_blank", "selectedOptions": key.correct_options}
        case HallucinationAnswerKey():
            return {"type": "hallucination", "sentenceIndexes": [e.index for e in key.errors]}
        case _:
            raise ValueError(f"no deterministic answer for {key.type}")


def wrong_answer(exercise: Exercise, key: AnswerKey) -> dict[str, Any]:
    match exercise, key:
        case ChoiceExercise(), ChoiceAnswerKey():
            other = next(o.id for o in exercise.options if o.id != key.correct_option_id)
            return {"type": "choice", "optionId": other}
        case _, OrderAnswerKey():
            return {"type": "order", "itemIds": list(reversed(key.correct_order))}
        case FillBlankExercise(), FillBlankAnswerKey():
            first = exercise.blanks[0]
            other = next(o.id for o in first.options if o.id != key.correct_options[first.id])
            return {
                "type": "fill_blank",
                "selectedOptions": {**key.correct_options, first.id: other},
            }
        case _:
            raise ValueError(f"no wrong answer builder for {key.type}")


class SingleUserVerifier:
    """Accepts any ID token as the given learner (App Check is disabled in these tests)."""

    def __init__(self, uid: str) -> None:
        self._user = CurrentUser(uid=uid, sign_in_provider="anonymous")

    def verify_id_token(self, id_token: str) -> CurrentUser | None:
        return self._user

    def verify_app_check_token(self, app_check_token: str) -> bool:
        return False
