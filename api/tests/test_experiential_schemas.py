"""Contracts of the story and live_check exercises."""

import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas.answers import SubmitAnswerRequest
from app.schemas.content import AnswerKey, Exercise
from app.schemas.firestore import LiveCheckSession
from app.schemas.live_check import StartLiveCheckResponse

exercise = TypeAdapter(Exercise)
answer_key = TypeAdapter(AnswerKey)

STORY = {
    "id": "u1-l4-q1",
    "lessonId": "u1-l4",
    "type": "story",
    "question": "ユイはどうする？",
    "title": "自由研究の前の夜",
    "scenes": [
        {
            "speaker": "narrator",
            "text": "締め切りの前の夜。",
            "illustration": {"prompt": "夜の勉強机、やわらかい水彩"},
        },
        {"speaker": "ai", "text": "日本で一番長い川は信濃川で、512km です。"},
    ],
    "options": [{"id": "a", "text": "そのまま書く"}, {"id": "b", "text": "教科書で確かめる"}],
}


def test_story_exercise_and_key_parse() -> None:
    parsed = exercise.validate_python(STORY)
    key = answer_key.validate_python(
        {
            "type": "story",
            "bestOptionId": "b",
            "outcomes": [
                {"optionId": "a", "scenes": [{"speaker": "teacher", "text": "367km だよ"}]},
                {"optionId": "b", "scenes": [{"speaker": "student", "text": "367km だった！"}]},
            ],
            "explanation": "数字は資料で確かめよう。",
        }
    )

    assert parsed.type == "story"
    assert parsed.scenes[0].illustration.image_path is None
    assert key.best_option_id == "b"


@pytest.mark.parametrize(
    "overrides",
    [
        {"scenes": []},
        {"options": [{"id": "a", "text": "x"}]},
        {"scenes": [{"speaker": "robot", "text": "x"}]},
    ],
)
def test_invalid_story_exercises_are_rejected(overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        exercise.validate_python(STORY | overrides)


def test_story_key_needs_an_outcome_for_the_best_option() -> None:
    with pytest.raises(ValidationError, match="best_option_id"):
        answer_key.validate_python(
            {
                "type": "story",
                "bestOptionId": "c",
                "outcomes": [
                    {"optionId": "a", "scenes": [{"speaker": "narrator", "text": "x"}]},
                    {"optionId": "b", "scenes": [{"speaker": "narrator", "text": "y"}]},
                ],
                "explanation": "z",
            }
        )


def test_live_check_exercise_defaults_and_limits() -> None:
    parsed = exercise.validate_python(
        {
            "id": "u3-l1-q1",
            "lessonId": "u3-l1",
            "type": "live_check",
            "question": "AI の答えから、まちがいを見つけよう",
            "theme": "富士山",
            "suggestions": ["富士山について教えて"],
            "errorCount": 1,
        }
    )

    assert (parsed.lookup_limit, parsed.max_length) == (2, 200)
    with pytest.raises(ValidationError):
        exercise.validate_python({**parsed.model_dump(by_alias=True), "errorCount": 3})


def test_answers_accept_story_and_live_check() -> None:
    for answer in (
        {"type": "story", "optionId": "b"},
        {"type": "live_check", "sessionId": "s1", "sentenceIndexes": [2]},
    ):
        request = SubmitAnswerRequest.model_validate({"exerciseId": "u1-l4-q1", "answer": answer})
        assert request.answer.type == answer["type"]
    with pytest.raises(ValidationError):
        SubmitAnswerRequest.model_validate(
            {
                "exerciseId": "u3-l1-q1",
                "answer": {"type": "live_check", "sessionId": "s1", "sentenceIndexes": [1, 1]},
            }
        )


def test_start_response_is_discriminated_by_status() -> None:
    parsed = TypeAdapter(StartLiveCheckResponse).validate_python(
        {"status": "blocked", "reasons": ["off_topic"], "message": "テーマからはなれているよ"}
    )

    assert parsed.status == "blocked"


def test_session_errors_and_sources_point_at_sentences() -> None:
    session = {
        "exerciseId": "u3-l1-q1",
        "lessonId": "u3-l1",
        "prompt": "富士山の高さは？",
        "sentences": [{"index": 0, "text": "a"}, {"index": 1, "text": "b"}],
        "errors": [{"index": 1, "errorType": "number", "correction": "c", "tip": "d"}],
        "sources": {"0": [{"title": "t", "uri": "https://example.com"}]},
        "lookupsUsed": 0,
        "answered": False,
        "createdAt": "2026-11-10T00:00:00Z",
    }
    LiveCheckSession.model_validate(session)

    with pytest.raises(ValidationError):
        bad_error = {"index": 5, "errorType": "number", "correction": "c", "tip": "d"}
        LiveCheckSession.model_validate(session | {"errors": [bad_error]})
    with pytest.raises(ValidationError):
        LiveCheckSession.model_validate(session | {"sources": {"7": []}})
