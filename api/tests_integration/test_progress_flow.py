"""The learning endpoints on the Firestore emulator with the seeded Unit 1."""

import datetime as dt
import threading
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import pytest
from fastapi.testclient import TestClient
from google.cloud.firestore import Client
from pydantic import TypeAdapter

from app.main import create_app
from app.repo.firestore import FirestoreLearningRepo
from app.schemas.answers import Answer, SubmitAnswerRequest
from app.schemas.firestore import (
    ATTEMPT_ITEMS_SUBCOLLECTION,
    ATTEMPTS_COLLECTION,
    PROGRESS_COLLECTION,
)
from app.services import learning
from tests.fakes import AUTH_HEADERS, NO_AI, NO_SPEECH, NOW, fixed_clock, make_settings
from tests_integration.support import (
    SEEDED_LESSON_ID,
    SingleUserVerifier,
    correct_answer,
    wrong_answer,
)

pytestmark = pytest.mark.integration

# Requests of one learner that arrive together (double taps, client retries). The emulator does
# not keep a retried transaction's place in line like production does, so heavy contention on
# one document can exhaust the retries there; keep these numbers realistic.
PARALLEL_EXERCISES = 6
PARALLEL_SAME_EXERCISE = 4

_answer = TypeAdapter(Answer)


def _client(repo: FirestoreLearningRepo, uid: str) -> TestClient:
    verifier = SingleUserVerifier(uid)
    app = create_app(make_settings(), verifier, repo, fixed_clock(NOW), NO_AI, NO_SPEECH)
    return TestClient(app)


def _post_answer(client: TestClient, exercise_id: str, answer: dict[str, Any]) -> dict[str, Any]:
    response = client.post(
        "/v1/answers", json={"exerciseId": exercise_id, "answer": answer}, headers=AUTH_HEADERS
    )
    assert response.status_code == 200, response.text
    return response.json()


def _stored_attempts(firestore: Client, uid: str) -> list[dict[str, Any]]:
    items = (
        firestore.collection(ATTEMPTS_COLLECTION)
        .document(uid)
        .collection(ATTEMPT_ITEMS_SUBCOLLECTION)
    )
    return [snapshot.to_dict() for snapshot in items.stream()]


def _stored_progress(firestore: Client, uid: str) -> dict[str, Any] | None:
    return firestore.collection(PROGRESS_COLLECTION).document(uid).get().to_dict()


def test_full_lesson_flow(repo: FirestoreLearningRepo, firestore_client: Client, uid: str) -> None:
    client = _client(repo, uid)
    lesson = repo.get_lesson(SEEDED_LESSON_ID)
    assert lesson is not None
    complete_url = f"/v1/lessons/{lesson.id}/complete"

    assert client.post(complete_url, headers=AUTH_HEADERS).status_code == 409
    # The first three exercises get a wrong answer first, then every exercise a correct one.
    for position, exercise_id in enumerate(lesson.exercise_ids):
        exercise, key = repo.get_exercise(exercise_id), repo.get_answer_key(exercise_id)
        assert exercise is not None and key is not None
        if position < 3:
            wrong = _post_answer(client, exercise_id, wrong_answer(exercise, key))
            assert (wrong["correct"], wrong["progress"]["xpGained"]) == (False, 0)
            assert wrong["result"]["explanation"]
        right = _post_answer(client, exercise_id, correct_answer(key))
        assert (right["correct"], right["progress"]["xpGained"]) == (True, 10)
    # Answering again correctly earns nothing.
    first_key = repo.get_answer_key(lesson.exercise_ids[0])
    assert first_key is not None
    again = _post_answer(client, lesson.exercise_ids[0], correct_answer(first_key))
    assert again["progress"] == {"xp": 60, "xpGained": 0, "streakDays": 0}

    completed = client.post(complete_url, headers=AUTH_HEADERS)
    repeated = client.post(complete_url, headers=AUTH_HEADERS)

    assert completed.status_code == 200, completed.text
    assert completed.json() == {
        "lessonId": lesson.id,
        "progress": {"xp": 80, "xpGained": 20, "streakDays": 1},
    }
    assert repeated.json()["progress"] == {"xp": 80, "xpGained": 0, "streakDays": 1}
    assert _stored_progress(firestore_client, uid) == {
        "xp": 80,
        "streakDays": 1,
        "lastStudiedOn": "2026-11-09",
        "freezeTickets": 0,
        "completedLessonIds": [lesson.id],
    }
    attempts = _stored_attempts(firestore_client, uid)
    assert len(attempts) == len(lesson.exercise_ids) + 3 + 1
    assert sum(a["xpGained"] for a in attempts) == 60
    assert {a["lessonId"] for a in attempts} == {lesson.id}
    assert all(isinstance(a["createdAt"], dt.datetime) for a in attempts)
    assert all(a["score"] is None and isinstance(a["correct"], bool) for a in attempts)


def _in_parallel(calls: list[Callable[[], Any]]) -> list[Any]:
    barrier = threading.Barrier(len(calls))

    def run(call: Callable[[], Any]) -> Any:
        barrier.wait()
        return call()

    with ThreadPoolExecutor(max_workers=len(calls)) as pool:
        return list(pool.map(run, calls))


def _submit(repo: FirestoreLearningRepo, uid: str, exercise_id: str) -> Callable[[], Any]:
    key = repo.get_answer_key(exercise_id)
    assert key is not None
    request = SubmitAnswerRequest(
        exercise_id=exercise_id, answer=_answer.validate_python(correct_answer(key))
    )
    attempt_id = uuid.uuid4().hex
    return lambda: learning.submit_answer(repo, uid, request, now=NOW, attempt_id=attempt_id)


def test_parallel_answers_do_not_lose_xp(
    repo: FirestoreLearningRepo, firestore_client: Client, uid: str
) -> None:
    lesson = repo.get_lesson(SEEDED_LESSON_ID)
    assert lesson is not None

    exercise_ids = lesson.exercise_ids[:PARALLEL_EXERCISES]

    responses = _in_parallel([_submit(repo, uid, e) for e in exercise_ids])

    assert all(r.progress.xp_gained == 10 for r in responses)
    assert sorted(r.progress.xp for r in responses) == [
        10 * n for n in range(1, PARALLEL_EXERCISES + 1)
    ]
    assert _stored_progress(firestore_client, uid)["xp"] == 10 * PARALLEL_EXERCISES
    assert len(_stored_attempts(firestore_client, uid)) == PARALLEL_EXERCISES


def test_parallel_correct_answers_to_one_exercise_earn_xp_once(
    repo: FirestoreLearningRepo, firestore_client: Client, uid: str
) -> None:
    exercise_id = f"{SEEDED_LESSON_ID}-q1"

    responses = _in_parallel(
        [_submit(repo, uid, exercise_id) for _ in range(PARALLEL_SAME_EXERCISE)]
    )

    assert sorted(r.progress.xp_gained for r in responses) == [0] * (PARALLEL_SAME_EXERCISE - 1) + [
        10
    ]
    assert _stored_progress(firestore_client, uid)["xp"] == 10
    attempts = _stored_attempts(firestore_client, uid)
    assert sorted(a["xpGained"] for a in attempts) == [0] * (PARALLEL_SAME_EXERCISE - 1) + [10]


def test_parallel_completions_award_the_bonus_once(
    repo: FirestoreLearningRepo, firestore_client: Client, uid: str
) -> None:
    lesson = repo.get_lesson(SEEDED_LESSON_ID)
    assert lesson is not None
    for exercise_id in lesson.exercise_ids:
        _submit(repo, uid, exercise_id)()

    responses = _in_parallel(
        [lambda: learning.complete_lesson(repo, uid, lesson.id, NOW) for _ in range(4)]
    )

    assert sorted(r.progress.xp_gained for r in responses) == [0, 0, 0, 20]
    progress = _stored_progress(firestore_client, uid)
    assert progress["xp"] == 10 * len(lesson.exercise_ids) + 20
    assert progress["streakDays"] == 1
    assert progress["completedLessonIds"] == [lesson.id]


def test_attempt_is_read_back_only_by_its_learner(repo: FirestoreLearningRepo, uid: str) -> None:
    exercise_id = repo.get_lesson(SEEDED_LESSON_ID).exercise_ids[0]  # type: ignore[union-attr]
    key = repo.get_answer_key(exercise_id)
    assert key is not None
    answered = _post_answer(_client(repo, uid), exercise_id, correct_answer(key))

    attempt = repo.get_attempt(uid, answered["attemptId"])

    assert attempt is not None
    assert (attempt.exercise_id, attempt.correct, attempt.xp_gained) == (exercise_id, True, 10)
    assert attempt.feedback_text == answered["result"]["explanation"]
    assert repo.get_attempt(f"{uid}-other", answered["attemptId"]) is None
    assert repo.get_attempt(uid, "missing") is None
