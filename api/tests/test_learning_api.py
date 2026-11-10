"""POST /v1/answers and POST /v1/lessons/{lessonId}/complete with the in-memory repo."""

import datetime as dt
import io
import json
import logging
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.logs import JsonFormatter
from app.repo.memory import InMemoryLearningRepo
from app.schemas.answers import SubmitAnswerResponse
from app.schemas.lessons import CompleteLessonResponse
from app.services.progress import NEW_PROGRESS
from tests.content import (
    CHOICE_ID,
    CORRECT_ANSWERS,
    FILL_ID,
    HALLUCINATION_ID,
    LESSON_ID,
    ORDER_ID,
    PROMPT_ID,
    PROMPT_LESSON_ID,
    WRONG_ANSWERS,
    make_repo,
)
from tests.fakes import AUTH_HEADERS, LEARNER, NOW, fixed_clock, make_learning_client

UID = LEARNER.uid


class Clock:
    """A clock the test can move forward."""

    def __init__(self, now: dt.datetime) -> None:
        self.now = now

    def __call__(self) -> dt.datetime:
        return self.now


@pytest.fixture
def repo() -> InMemoryLearningRepo:
    return make_repo()


@pytest.fixture
def clock() -> Clock:
    return Clock(NOW)


@pytest.fixture
def client(repo: InMemoryLearningRepo, clock: Clock) -> TestClient:
    return make_learning_client(repo, clock)


def _answer(client: TestClient, exercise_id: str, answer: dict[str, Any]) -> Any:
    return client.post(
        "/v1/answers", json={"exerciseId": exercise_id, "answer": answer}, headers=AUTH_HEADERS
    )


def _complete(client: TestClient, lesson_id: str = LESSON_ID) -> Any:
    return client.post(f"/v1/lessons/{lesson_id}/complete", headers=AUTH_HEADERS)


def _error(response: Any, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["error"]["code"] == code


# ---- POST /v1/answers -------------------------------------------------------------------


def test_correct_answer_returns_result_and_records_the_attempt(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    response = _answer(client, CHOICE_ID, CORRECT_ANSWERS[CHOICE_ID])

    assert response.status_code == 200
    body = response.json()
    SubmitAnswerResponse.model_validate(body)
    assert body == {
        "attemptId": body["attemptId"],
        "correct": True,
        "result": {
            "type": "choice",
            "correctOptionId": "b",
            "explanation": "予測だよ。\nb が正解。",
        },
        "progress": {"xp": 10, "xpGained": 10, "streakDays": 0},
    }
    attempt = repo.attempts[UID][body["attemptId"]]
    assert attempt.model_dump(mode="json") == {
        "exerciseId": CHOICE_ID,
        "lessonId": LESSON_ID,
        "type": "choice",
        "correct": True,
        "score": None,
        "answer": {"type": "choice", "optionId": "b"},
        "feedbackText": "予測だよ。\nb が正解。",
        "xpGained": 10,
        "createdAt": "2026-11-09T01:00:00Z",
    }
    # The first write creates progress from the empty state.
    assert repo.progress[UID].model_dump() == {**NEW_PROGRESS.model_dump(), "xp": 10}


def test_only_the_first_correct_attempt_earns_xp(client: TestClient) -> None:
    wrong = _answer(client, ORDER_ID, WRONG_ANSWERS[ORDER_ID]).json()
    first = _answer(client, ORDER_ID, CORRECT_ANSWERS[ORDER_ID]).json()
    again = _answer(client, ORDER_ID, CORRECT_ANSWERS[ORDER_ID]).json()

    assert [r["correct"] for r in (wrong, first, again)] == [False, True, True]
    assert [r["progress"]["xpGained"] for r in (wrong, first, again)] == [0, 10, 0]
    assert again["progress"]["xp"] == 10
    assert len({r["attemptId"] for r in (wrong, first, again)}) == 3


def test_wrong_answer_is_recorded_with_zero_xp(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    body = _answer(client, FILL_ID, WRONG_ANSWERS[FILL_ID]).json()

    assert body["correct"] is False
    assert body["result"] == {
        "type": "fill_blank",
        "correctOptions": {"p": "a", "q": "d"},
        "explanation": "a と d",
    }
    assert body["progress"] == {"xp": 0, "xpGained": 0, "streakDays": 0}
    assert repo.attempts[UID][body["attemptId"]].correct is False


def test_hallucination_result_lists_found_missed_and_false_alarms(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    body = _answer(
        client, HALLUCINATION_ID, {"type": "hallucination", "sentenceIndexes": [0, 1]}
    ).json()

    assert body["correct"] is False
    result = body["result"]
    assert (result["found"], result["missed"], result["falseAlarms"]) == ([1], [3], [0])
    assert [e["index"] for e in result["errors"]] == [1, 3]
    assert set(result["errors"][0]) == {"index", "errorType", "correction", "tip"}
    attempt = repo.attempts[UID][body["attemptId"]]
    assert attempt.feedback_text == "3776 m です。\n数字を確認。\n文化遺産です。\n種類に注意。"


def test_xp_is_kept_per_learner_progress(client: TestClient) -> None:
    for exercise_id in (CHOICE_ID, ORDER_ID, FILL_ID, HALLUCINATION_ID):
        last = _answer(client, exercise_id, CORRECT_ANSWERS[exercise_id]).json()

    assert last["progress"] == {"xp": 40, "xpGained": 10, "streakDays": 0}


def test_unknown_exercise_is_not_found(client: TestClient, repo: InMemoryLearningRepo) -> None:
    _error(_answer(client, "u9-l9-q9", {"type": "choice", "optionId": "a"}), 404, "not_found")
    assert repo.attempts == {}


@pytest.mark.parametrize(
    ("exercise_id", "answer"),
    [
        (CHOICE_ID, {"type": "order", "itemIds": ["a", "b"]}),
        (CHOICE_ID, {"type": "choice", "optionId": "z"}),
        (ORDER_ID, {"type": "order", "itemIds": ["input", "predict"]}),
        (FILL_ID, {"type": "fill_blank", "selectedOptions": {"p": "a"}}),
        (HALLUCINATION_ID, {"type": "hallucination", "sentenceIndexes": [9]}),
        (PROMPT_ID, {"type": "choice", "optionId": "a"}),
    ],
    ids=["type-mismatch", "unknown-option", "not-permutation", "blanks", "index", "prompt"],
)
def test_answer_that_does_not_fit_the_exercise_is_bad_request(
    client: TestClient, repo: InMemoryLearningRepo, exercise_id: str, answer: dict[str, Any]
) -> None:
    _error(_answer(client, exercise_id, answer), 400, "bad_request")
    assert repo.attempts == {}
    assert repo.progress == {}


def test_malformed_body_is_bad_request(client: TestClient) -> None:
    _error(_answer(client, CHOICE_ID, {"type": "choice"}), 400, "bad_request")


def test_missing_answer_key_is_an_internal_error(repo: InMemoryLearningRepo) -> None:
    del repo.answer_keys[CHOICE_ID]
    client = TestClient(
        make_learning_client(repo, fixed_clock(NOW)).app, raise_server_exceptions=False
    )

    _error(_answer(client, CHOICE_ID, CORRECT_ANSWERS[CHOICE_ID]), 500, "internal")
    assert repo.attempts == {}


@pytest.fixture
def answer_log() -> Iterator[io.StringIO]:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("app.answers")
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    yield stream
    logger.removeHandler(handler)


def test_each_graded_answer_logs_one_line_without_answer_contents(
    client: TestClient, answer_log: io.StringIO
) -> None:
    body = _answer(client, FILL_ID, WRONG_ANSWERS[FILL_ID]).json()
    _answer(client, CHOICE_ID, {"type": "choice", "optionId": "z"})  # 400: not graded

    [line] = [json.loads(raw) for raw in answer_log.getvalue().splitlines()]
    assert line["message"] == "answer graded"
    assert {k: line[k] for k in ("attemptId", "exerciseId", "exerciseType", "correct")} == {
        "attemptId": body["attemptId"],
        "exerciseId": FILL_ID,
        "exerciseType": "fill_blank",
        "correct": False,
    }
    assert line["xpGained"] == 0
    assert "selectedOptions" not in answer_log.getvalue()
    assert UID not in answer_log.getvalue()


# ---- POST /v1/lessons/{lessonId}/complete -----------------------------------------------


def _answer_all(client: TestClient, answers: dict[str, dict[str, Any]]) -> None:
    for exercise_id, answer in answers.items():
        assert _answer(client, exercise_id, answer).status_code == 200


def test_unknown_lesson_is_not_found(client: TestClient) -> None:
    _error(_complete(client, "u9-l9"), 404, "not_found")


def test_lesson_with_an_unanswered_exercise_is_a_conflict(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    _answer_all(client, {k: v for k, v in CORRECT_ANSWERS.items() if k != FILL_ID})
    before = repo.progress[UID]

    _error(_complete(client), 409, "conflict")
    assert repo.progress[UID] == before


def test_new_learner_cannot_complete_without_answers(
    client: TestClient, repo: InMemoryLearningRepo
) -> None:
    _error(_complete(client), 409, "conflict")
    assert repo.progress == {}


def test_prompt_lesson_needs_a_prompt_attempt(client: TestClient) -> None:
    _error(_complete(client, PROMPT_LESSON_ID), 409, "conflict")


def test_completion_awards_xp_once_and_updates_the_streak(
    client: TestClient, repo: InMemoryLearningRepo, clock: Clock
) -> None:
    # Two correct (20 XP) and two wrong answers.
    _answer_all(
        client, {CHOICE_ID: CORRECT_ANSWERS[CHOICE_ID], ORDER_ID: CORRECT_ANSWERS[ORDER_ID]}
    )
    _answer_all(
        client, {FILL_ID: WRONG_ANSWERS[FILL_ID], HALLUCINATION_ID: WRONG_ANSWERS[HALLUCINATION_ID]}
    )

    first = _complete(client)

    assert first.status_code == 200
    CompleteLessonResponse.model_validate(first.json())
    assert first.json() == {
        "lessonId": LESSON_ID,
        "progress": {"xp": 40, "xpGained": 20, "streakDays": 1},
    }
    assert repo.progress[UID].model_dump(mode="json") == {
        "xp": 40,
        "streakDays": 1,
        "lastStudiedOn": "2026-11-09",
        "freezeTickets": 0,
        "completedLessonIds": [LESSON_ID],
    }

    again_same_day = _complete(client).json()
    clock.now = NOW + dt.timedelta(days=1)
    next_day = _complete(client).json()

    assert again_same_day["progress"] == {"xp": 40, "xpGained": 0, "streakDays": 1}
    assert next_day["progress"] == {"xp": 40, "xpGained": 0, "streakDays": 2}
    assert repo.progress[UID].completed_lesson_ids == [LESSON_ID]
    assert repo.progress[UID].last_studied_on == dt.date(2026, 11, 10)


def test_streak_uses_the_date_in_tokyo(
    client: TestClient, repo: InMemoryLearningRepo, clock: Clock
) -> None:
    _answer_all(client, CORRECT_ANSWERS)
    # 2026-11-09 23:30 JST, then 00:10 JST the next day (still the 9th in UTC).
    clock.now = dt.datetime(2026, 11, 9, 14, 30, tzinfo=dt.UTC)
    assert _complete(client).json()["progress"]["streakDays"] == 1
    clock.now = dt.datetime(2026, 11, 9, 15, 10, tzinfo=dt.UTC)
    assert _complete(client).json()["progress"]["streakDays"] == 2
    assert repo.progress[UID].last_studied_on == dt.date(2026, 11, 10)
