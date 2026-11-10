import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas.content import AnswerKey, Exercise, Lesson

exercise = TypeAdapter(Exercise)
answer_key = TypeAdapter(AnswerKey)


def hallucination(**overrides: object) -> dict[str, object]:
    body: dict[str, object] = {
        "id": "u3-l1-q1",
        "lessonId": "u3-l1",
        "type": "hallucination",
        "question": "まちがっている文をタップしよう",
        "topic": "光合成",
        "sentences": [
            {"index": 0, "text": "光合成は植物が栄養をつくるしくみです。"},
            {"index": 1, "text": "光合成は主に根で行われます。"},
            {"index": 2, "text": "光合成には光が必要です。"},
        ],
        "errorCount": 1,
    }
    return body | overrides


def test_exercise_is_parsed_by_type_from_camel_case_json() -> None:
    parsed = exercise.validate_python(hallucination())

    assert parsed.type == "hallucination"
    assert parsed.error_count == 1
    assert exercise.dump_python(parsed, mode="json")["lessonId"] == "u3-l1"


@pytest.mark.parametrize(
    "overrides",
    [
        {"type": "essay"},
        {"errorCount": 3},
        {"sentences": [{"index": 1, "text": "a"}, {"index": 0, "text": "b"}]},
        {"id": "U3_L1"},
        {"unknownField": True},
    ],
)
def test_invalid_hallucination_exercises_are_rejected(overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        exercise.validate_python(hallucination(**overrides))


def test_choice_options_must_have_unique_ids() -> None:
    with pytest.raises(ValidationError, match="unique"):
        exercise.validate_python(
            {
                "id": "u1-l1-q1",
                "lessonId": "u1-l1",
                "type": "choice",
                "question": "AI は何をしている？",
                "options": [{"id": "a", "text": "予測"}, {"id": "a", "text": "検索"}],
            }
        )


def test_fill_blank_template_must_contain_every_blank_once() -> None:
    body = {
        "id": "u2-l1-q2",
        "lessonId": "u2-l1",
        "type": "fill_blank",
        "question": "空欄をうめよう",
        "template": "あなたは{{role}}です。",
        "blanks": [
            {"id": "role", "options": [{"id": "a", "text": "先生"}, {"id": "b", "text": "犬"}]},
            {"id": "goal", "options": [{"id": "a", "text": "要約"}, {"id": "b", "text": "翻訳"}]},
        ],
    }

    with pytest.raises(ValidationError, match="goal"):
        exercise.validate_python(body)


def test_lesson_exercise_ids_must_be_unique() -> None:
    with pytest.raises(ValidationError, match="unique"):
        Lesson.model_validate(
            {
                "id": "u1-l1",
                "unitId": "u1",
                "order": 1,
                "title": "AI ってなに？",
                "exerciseIds": ["u1-l1-q1", "u1-l1-q1"],
            }
        )


def test_hallucination_answer_key_rejects_duplicate_indexes() -> None:
    error = {"index": 1, "errorType": "fact", "correction": "葉で行われる", "tip": "場所を確認"}

    with pytest.raises(ValidationError, match="unique"):
        answer_key.validate_python({"type": "hallucination", "errors": [error, error]})


def test_a_clean_answer_is_a_valid_hallucination_exercise_and_key() -> None:
    assert exercise.validate_python(hallucination(errorCount=0)).error_count == 0
    assert answer_key.validate_python({"type": "hallucination", "errors": []}).errors == []
