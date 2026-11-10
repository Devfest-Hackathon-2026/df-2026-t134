"""Story (picture-story) answers: grading and POST /v1/answers."""

from typing import Any

import pytest
from fastapi.testclient import TestClient
from pydantic import TypeAdapter

from app.repo.memory import InMemoryLearningRepo
from app.schemas.answers import Answer, StoryResult, SubmitAnswerResponse
from app.schemas.content import AnswerKey, Exercise, Lesson
from app.services.grading import answer_problem, grade
from tests.fakes import AUTH_HEADERS, LEARNER, NOW, fixed_clock, make_learning_client

LESSON_ID = "s1-l1"
STORY_ID = f"{LESSON_ID}-q1"
CHOICE_ID = f"{LESSON_ID}-q2"

STORY: dict[str, Any] = {
    "id": STORY_ID,
    "lessonId": LESSON_ID,
    "type": "story",
    "title": "自由研究",
    "question": "ユイはどうする？",
    "scenes": [
        {
            "speaker": "narrator",
            "text": "ユイは自由研究をしています。",
            "illustration": {
                "prompt": "Yui at her desk",
                "imagePath": "images/scenes/" + "a" * 64 + ".png",
            },
        },
        {"speaker": "ai", "text": "ホタルは電気で光ります。"},
    ],
    "options": [
        {"id": "copy", "text": "そのまま書く"},
        {"id": "check", "text": "図鑑で確かめる"},
    ],
}

STORY_KEY: dict[str, Any] = {
    "type": "story",
    "bestOptionId": "check",
    "outcomes": [
        {
            "optionId": "copy",
            "scenes": [
                {"speaker": "teacher", "text": "どこで調べたのかな？"},
                {
                    "speaker": "student",
                    "text": "まちがえちゃった…。",
                    "audioPath": "audio/lines/" + "b" * 64 + ".mp3",
                },
            ],
        },
        {
            "optionId": "check",
            "scenes": [{"speaker": "student", "text": "化学反応だった！"}],
        },
    ],
    "explanation": "AI 以外の情報源で確かめよう。",
}

_answer = TypeAdapter(Answer)
_exercise = TypeAdapter(Exercise)
_key = TypeAdapter(AnswerKey)


def _story_answer(option_id: str) -> Any:
    return _answer.validate_python({"type": "story", "optionId": option_id})


def _repo() -> InMemoryLearningRepo:
    choice = {
        "id": CHOICE_ID,
        "lessonId": LESSON_ID,
        "type": "choice",
        "question": "どれ？",
        "options": [{"id": "a", "text": "A"}, {"id": "b", "text": "B"}],
    }
    lesson = Lesson.model_validate(
        {
            "id": LESSON_ID,
            "unitId": "s1",
            "order": 1,
            "title": "紙しばい",
            "exerciseIds": [STORY_ID, CHOICE_ID],
        }
    )
    return InMemoryLearningRepo(
        [lesson],
        [_exercise.validate_python(STORY), _exercise.validate_python(choice)],
        {
            STORY_ID: _key.validate_python(STORY_KEY),
            CHOICE_ID: _key.validate_python(
                {"type": "choice", "correctOptionId": "a", "explanation": "A"}
            ),
        },
    )


# ---- grading ------------------------------------------------------------------------------


def test_best_option_is_correct_and_plays_its_outcome() -> None:
    graded = grade(_key.validate_python(STORY_KEY), _story_answer("check"))

    assert graded.correct
    assert graded.result.model_dump(mode="json", exclude_none=True) == {
        "type": "story",
        "bestOptionId": "check",
        "outcome": [{"speaker": "student", "text": "化学反応だった！"}],
        "explanation": "AI 以外の情報源で確かめよう。",
    }
    assert graded.feedback_text == "化学反応だった！\nAI 以外の情報源で確かめよう。"


def test_other_option_is_wrong_and_plays_the_outcome_of_that_option() -> None:
    graded = grade(_key.validate_python(STORY_KEY), _story_answer("copy"))

    assert not graded.correct
    assert isinstance(graded.result, StoryResult)
    assert [scene.text for scene in graded.result.outcome] == [
        "どこで調べたのかな？",
        "まちがえちゃった…。",
    ]
    # Generated media paths come back as they were seeded.
    assert graded.result.outcome[1].audio_path == "audio/lines/" + "b" * 64 + ".mp3"
    assert graded.feedback_text == (
        "どこで調べたのかな？\nまちがえちゃった…。\nAI 以外の情報源で確かめよう。"
    )


def test_option_outside_the_exercise_cannot_be_graded() -> None:
    exercise = _exercise.validate_python(STORY)

    assert answer_problem(exercise, _story_answer("check")) is None
    assert answer_problem(exercise, _story_answer("guess")) == (
        "optionId is not an option of this exercise"
    )


def test_story_answer_does_not_fit_another_exercise_type() -> None:
    choice = _repo().get_exercise(CHOICE_ID)
    assert choice is not None

    assert answer_problem(choice, _story_answer("a")) == (
        "answer type story does not match exercise type choice"
    )


def test_key_without_the_outcome_of_a_valid_option_is_corrupt_content() -> None:
    # A key that passes its own schema but lacks an outcome the exercise needs.
    other = {"optionId": "other", "scenes": [{"speaker": "narrator", "text": "べつのお話"}]}
    key = _key.validate_python({**STORY_KEY, "outcomes": [STORY_KEY["outcomes"][1], other]})
    with pytest.raises(ValueError, match="no outcome for option copy"):
        grade(key, _story_answer("copy"))


# ---- POST /v1/answers ---------------------------------------------------------------------


@pytest.fixture
def repo() -> InMemoryLearningRepo:
    return _repo()


@pytest.fixture
def client(repo: InMemoryLearningRepo) -> TestClient:
    return make_learning_client(repo, fixed_clock(NOW))


def _post(client: TestClient, option_id: str) -> Any:
    return client.post(
        "/v1/answers",
        json={"exerciseId": STORY_ID, "answer": {"type": "story", "optionId": option_id}},
        headers=AUTH_HEADERS,
    )


def test_story_answer_is_graded_recorded_and_earns_xp_once(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    wrong = _post(client, "copy")
    first = _post(client, "check")
    again = _post(client, "check")

    for response in (wrong, first, again):
        assert response.status_code == 200, response.text
        SubmitAnswerResponse.model_validate(response.json())
    bodies = [r.json() for r in (wrong, first, again)]
    assert [b["correct"] for b in bodies] == [False, True, True]
    assert [b["progress"]["xpGained"] for b in bodies] == [0, 10, 0]
    # Unset media fields are sent as null (the app shows the text only).
    assert bodies[0]["result"]["outcome"][0] == {
        "speaker": "teacher",
        "text": "どこで調べたのかな？",
        "audioPath": None,
        "illustration": None,
    }
    assert bodies[1]["result"]["bestOptionId"] == "check"
    attempt = repo.attempts[LEARNER.uid][bodies[1]["attemptId"]]
    assert attempt.type == "story"
    assert attempt.answer == {"type": "story", "optionId": "check"}
    assert attempt.feedback_text == "化学反応だった！\nAI 以外の情報源で確かめよう。"


def test_story_option_outside_the_exercise_is_bad_request(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    response = _post(client, "guess")

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"
    assert LEARNER.uid not in repo.attempts


def test_story_answer_counts_for_lesson_completion(client: TestClient) -> None:
    _post(client, "copy")
    client.post(
        "/v1/answers",
        json={"exerciseId": CHOICE_ID, "answer": {"type": "choice", "optionId": "a"}},
        headers=AUTH_HEADERS,
    )

    response = client.post(f"/v1/lessons/{LESSON_ID}/complete", headers=AUTH_HEADERS)

    assert response.status_code == 200, response.text
