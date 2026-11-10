from typing import Any

import pytest
from pydantic import TypeAdapter

from app.schemas.answers import Answer, HallucinationResult
from app.schemas.content import ChoiceAnswerKey
from app.services.grading import answer_problem, grade
from tests.content import (
    ANSWER_KEYS,
    CHOICE_ID,
    CORRECT_ANSWERS,
    EXERCISES,
    FILL_ID,
    HALLUCINATION_ID,
    ORDER_ID,
    PROMPT_ID,
    WRONG_ANSWERS,
)

_answer = TypeAdapter(Answer)
GRADED_IDS = [CHOICE_ID, ORDER_ID, FILL_ID, HALLUCINATION_ID]


def _grade(exercise_id: str, answer: dict[str, Any]):
    parsed = _answer.validate_python(answer)
    assert answer_problem(EXERCISES[exercise_id], parsed) is None
    return grade(ANSWER_KEYS[exercise_id], parsed)


@pytest.mark.parametrize("exercise_id", GRADED_IDS)
def test_correct_answer_is_correct(exercise_id: str) -> None:
    assert _grade(exercise_id, CORRECT_ANSWERS[exercise_id]).correct


@pytest.mark.parametrize("exercise_id", GRADED_IDS)
def test_wrong_answer_is_wrong(exercise_id: str) -> None:
    assert not _grade(exercise_id, WRONG_ANSWERS[exercise_id]).correct


def test_choice_result_has_correct_option_and_explanation() -> None:
    graded = _grade(CHOICE_ID, WRONG_ANSWERS[CHOICE_ID])

    assert graded.result.model_dump(mode="json") == {
        "type": "choice",
        "correctOptionId": "b",
        "explanation": "予測だよ。\nb が正解。",
    }
    assert graded.feedback_text == "予測だよ。\nb が正解。"


def test_order_must_match_the_exact_sequence() -> None:
    graded = _grade(ORDER_ID, {"type": "order", "itemIds": ["input", "append", "predict"]})

    assert not graded.correct
    assert graded.result.model_dump(mode="json")["correctOrder"] == ["input", "predict", "append"]


def test_fill_blank_needs_every_blank_right() -> None:
    one_wrong = _grade(FILL_ID, {"type": "fill_blank", "selectedOptions": {"p": "b", "q": "d"}})

    assert not one_wrong.correct
    assert one_wrong.result.model_dump(mode="json")["correctOptions"] == {"p": "a", "q": "d"}


def _hallucination(indexes: list[int]) -> tuple[bool, HallucinationResult]:
    graded = _grade(HALLUCINATION_ID, {"type": "hallucination", "sentenceIndexes": indexes})
    assert isinstance(graded.result, HallucinationResult)
    return graded.correct, graded.result


def test_hallucination_all_found_without_false_alarms_is_correct() -> None:
    correct, result = _hallucination([3, 1])

    assert correct
    assert (result.found, result.missed, result.false_alarms) == ([1, 3], [], [])
    # Errors come back sorted by sentence index.
    assert [error.index for error in result.errors] == [1, 3]


def test_hallucination_missed_error_is_wrong() -> None:
    correct, result = _hallucination([1])

    assert not correct
    assert (result.found, result.missed, result.false_alarms) == ([1], [3], [])


def test_hallucination_false_alarm_is_wrong_even_when_all_errors_are_found() -> None:
    correct, result = _hallucination([0, 1, 3])

    assert not correct
    assert (result.found, result.missed, result.false_alarms) == ([1, 3], [], [0])


def test_hallucination_empty_answer_misses_everything() -> None:
    correct, result = _hallucination([])

    assert not correct
    assert (result.found, result.missed, result.false_alarms) == ([], [1, 3], [])


def test_hallucination_feedback_joins_corrections_and_tips_in_sentence_order() -> None:
    graded = _grade(HALLUCINATION_ID, CORRECT_ANSWERS[HALLUCINATION_ID])

    assert graded.feedback_text == "3776 m です。\n数字を確認。\n文化遺産です。\n種類に注意。"


@pytest.mark.parametrize(
    ("exercise_id", "answer", "problem"),
    [
        (CHOICE_ID, {"type": "order", "itemIds": ["a", "b"]}, "does not match"),
        (ORDER_ID, {"type": "choice", "optionId": "a"}, "does not match"),
        (HALLUCINATION_ID, {"type": "fill_blank", "selectedOptions": {"p": "a"}}, "does not match"),
        (CHOICE_ID, {"type": "choice", "optionId": "z"}, "not an option"),
        (ORDER_ID, {"type": "order", "itemIds": ["input", "predict"]}, "ordering of every item"),
        (
            ORDER_ID,
            {"type": "order", "itemIds": ["input", "predict", "x"]},
            "ordering of every item",
        ),
        (
            ORDER_ID,
            {"type": "order", "itemIds": ["input", "predict", "append", "x"]},
            "ordering of every item",
        ),
        (FILL_ID, {"type": "fill_blank", "selectedOptions": {"p": "a"}}, "one entry per blank"),
        (
            FILL_ID,
            {"type": "fill_blank", "selectedOptions": {"p": "a", "q": "d", "r": "a"}},
            "one entry per blank",
        ),
        (FILL_ID, {"type": "fill_blank", "selectedOptions": {"p": "c", "q": "d"}}, "not in its"),
        (HALLUCINATION_ID, {"type": "hallucination", "sentenceIndexes": [4]}, "outside"),
        (PROMPT_ID, {"type": "choice", "optionId": "a"}, "/v1/prompt/evaluate"),
    ],
)
def test_answer_problems(exercise_id: str, answer: dict[str, Any], problem: str) -> None:
    message = answer_problem(EXERCISES[exercise_id], _answer.validate_python(answer))

    assert message is not None
    assert problem in message


def test_answer_key_of_another_type_is_treated_as_corrupt_content() -> None:
    key = ChoiceAnswerKey(type="choice", correct_option_id="a", explanation="x")

    with pytest.raises(ValueError, match="does not match"):
        grade(key, _answer.validate_python(CORRECT_ANSWERS[ORDER_ID]))
