import datetime as dt

import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas.answers import SubmitAnswerRequest
from app.schemas.firestore import Attempt
from app.schemas.prompt import EvaluatePromptRequest, EvaluatePromptResponse


def test_submit_answer_accepts_each_answer_type() -> None:
    for answer in (
        {"type": "choice", "optionId": "a"},
        {"type": "order", "itemIds": ["a", "b"]},
        {"type": "fill_blank", "selectedOptions": {"role": "a"}},
        {"type": "hallucination", "sentenceIndexes": []},
    ):
        request = SubmitAnswerRequest.model_validate({"exerciseId": "u1-l1-q1", "answer": answer})
        assert request.answer.type == answer["type"]


@pytest.mark.parametrize(
    "answer",
    [
        {"type": "prompt", "prompt": "hi"},
        {"type": "order", "itemIds": ["a", "a"]},
        {"type": "hallucination", "sentenceIndexes": [-1]},
        {"type": "hallucination", "sentenceIndexes": [1, 1]},
    ],
)
def test_submit_answer_rejects_invalid_answers(answer: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        SubmitAnswerRequest.model_validate({"exerciseId": "u1-l1-q1", "answer": answer})


@pytest.mark.parametrize("prompt", ["", "   ", "あ" * 1001])
def test_prompt_text_length_is_checked_after_trimming(prompt: str) -> None:
    with pytest.raises(ValidationError):
        EvaluatePromptRequest.model_validate({"exerciseId": "u2-l3-q4", "prompt": prompt})


def test_prompt_response_is_discriminated_by_status() -> None:
    parsed = TypeAdapter(EvaluatePromptResponse).validate_python(
        {"status": "blocked", "reasons": ["personal_info"], "message": "電話番号が含まれています"}
    )

    assert parsed.status == "blocked"


def attempt(**overrides: object) -> dict[str, object]:
    body: dict[str, object] = {
        "exerciseId": "u1-l1-q1",
        "lessonId": "u1-l1",
        "type": "choice",
        "correct": True,
        "score": None,
        "answer": {"type": "choice", "optionId": "a"},
        "feedbackText": "正解！",
        "xpGained": 10,
        "createdAt": dt.datetime(2026, 11, 9, tzinfo=dt.UTC),
    }
    return body | overrides


def test_attempt_grading_fields_follow_exercise_type() -> None:
    Attempt.model_validate(attempt())
    Attempt.model_validate(attempt(type="prompt", correct=None, score=7))

    with pytest.raises(ValidationError):
        Attempt.model_validate(attempt(type="prompt", correct=True, score=None))
    with pytest.raises(ValidationError):
        Attempt.model_validate(attempt(correct=None, score=5))
