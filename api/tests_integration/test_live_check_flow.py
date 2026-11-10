"""The live check session lifecycle on the Firestore emulator with the seeded Unit 3 (the model
is a fake; only Firestore is real)."""

import datetime as dt
import threading
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import pytest
from fastapi.testclient import TestClient
from google.cloud.firestore import Client

from app.ai import GroundedSegment, GroundedText, Source
from app.errors import ApiError
from app.main import create_app
from app.repo.firestore import FirestoreLearningRepo
from app.schemas.content import LiveCheckExercise
from app.schemas.firestore import LIVE_CHECK_ITEMS_SUBCOLLECTION, LIVE_CHECKS_COLLECTION
from app.services import live_check
from app.services.error_injection import InjectedError, Injection
from tests.fakes import (
    AUTH_HEADERS,
    NO_SPEECH,
    NOW,
    FakeAnswerer,
    FakeGenerator,
    fixed_clock,
    make_settings,
)
from tests_integration.support import SingleUserVerifier

pytestmark = pytest.mark.integration

# Seeded from content/units/u3 by the make target.
LIVE_CHECK_ID = "u3-l1-q3"

SENTENCES = [
    "富士山は日本でいちばん高い山です。",
    "高さは 3776 メートルです。",
    "静岡県と山梨県にまたがっています。",
    "2013 年に世界文化遺産になりました。",
]
PAGE = Source(title="example.jp", uri="https://example.jp/fuji")
ANSWER = GroundedText(
    text="OK\n" + "\n".join(SENTENCES),
    sources=(PAGE,),
    segments=(GroundedSegment(text=SENTENCES[1], sources=(PAGE,)),),
)
INJECTION = Injection(
    errors=[
        InjectedError(
            index=1, error_type="number", wrong_text="高さは 5776 メートルです。", tip="数字。"
        )
    ]
)


def _client(repo: FirestoreLearningRepo, uid: str, daily_limit: int = 10) -> TestClient:
    settings = make_settings().model_copy(update={"live_check_daily_limit": daily_limit})
    app = create_app(
        settings,
        SingleUserVerifier(uid),
        repo,
        fixed_clock(NOW),
        FakeGenerator(INJECTION, INJECTION),
        NO_SPEECH,
        FakeAnswerer(ANSWER, ANSWER),
    )
    return TestClient(app)


def _stored(firestore: Client, uid: str, session_id: str) -> dict[str, Any]:
    snapshot = (
        firestore.collection(LIVE_CHECKS_COLLECTION)
        .document(uid)
        .collection(LIVE_CHECK_ITEMS_SUBCOLLECTION)
        .document(session_id)
        .get()
    )
    assert snapshot.exists
    return snapshot.to_dict()


def _start(client: TestClient) -> Any:
    return client.post(
        "/v1/live-checks",
        json={"exerciseId": LIVE_CHECK_ID, "prompt": "富士山の高さは？"},
        headers=AUTH_HEADERS,
    )


def test_session_is_started_looked_up_answered_once(
    repo: FirestoreLearningRepo, firestore_client: Client, uid: str
) -> None:
    exercise = repo.get_exercise(LIVE_CHECK_ID)
    assert isinstance(exercise, LiveCheckExercise)
    client = _client(repo, uid)

    started = _start(client)
    assert started.status_code == 200, started.text
    session_id = started.json()["sessionId"]
    stored = _stored(firestore_client, uid, session_id)
    assert isinstance(stored["createdAt"], dt.datetime)
    assert stored["sources"]["1"] == [{"title": PAGE.title, "uri": PAGE.uri}]
    assert stored["errors"][0]["correction"] == SENTENCES[1]

    lookup = client.post(
        f"/v1/live-checks/{session_id}/lookup", json={"sentenceIndex": 1}, headers=AUTH_HEADERS
    )
    assert lookup.json()["lookupsLeft"] == exercise.lookup_limit - 1
    answer = {"type": "live_check", "sessionId": session_id, "sentenceIndexes": [1]}
    body = {"exerciseId": LIVE_CHECK_ID, "answer": answer}
    first = client.post("/v1/answers", json=body, headers=AUTH_HEADERS)
    again = client.post("/v1/answers", json=body, headers=AUTH_HEADERS)

    assert first.status_code == 200, first.text
    assert (first.json()["correct"], first.json()["progress"]["xpGained"]) == (True, 10)
    assert again.status_code == 409
    stored = _stored(firestore_client, uid, session_id)
    assert (stored["answered"], stored["lookupsUsed"]) == (True, 1)
    # Another learner cannot see or use the session.
    other = _client(repo, f"{uid}-other")
    response = other.post(
        f"/v1/live-checks/{session_id}/lookup", json={"sentenceIndex": 0}, headers=AUTH_HEADERS
    )
    assert response.status_code == 404


def test_daily_limit_counts_the_stored_sessions(repo: FirestoreLearningRepo, uid: str) -> None:
    client = _client(repo, uid, daily_limit=1)

    assert _start(client).status_code == 200
    assert _start(client).status_code == 429
    assert repo.count_live_checks_since(uid, NOW) == 1
    assert repo.count_live_checks_since(uid, NOW + dt.timedelta(seconds=1)) == 0


def _in_parallel(calls: list[Callable[[], Any]]) -> list[Any]:
    barrier = threading.Barrier(len(calls))

    def run(call: Callable[[], Any]) -> Any:
        barrier.wait()
        try:
            return call()
        except ApiError as error:
            return error

    with ThreadPoolExecutor(max_workers=len(calls)) as pool:
        return list(pool.map(run, calls))


def test_parallel_lookups_never_exceed_the_limit(
    repo: FirestoreLearningRepo, firestore_client: Client, uid: str
) -> None:
    exercise = repo.get_exercise(LIVE_CHECK_ID)
    assert isinstance(exercise, LiveCheckExercise)
    session_id = _start(_client(repo, uid)).json()["sessionId"]
    tries = exercise.lookup_limit + 2

    results = _in_parallel(
        [lambda: live_check.lookup_sources(repo, uid, session_id, 0) for _ in range(tries)]
    )

    errors = [r for r in results if isinstance(r, ApiError)]
    assert len(results) - len(errors) == exercise.lookup_limit
    assert {e.status_code for e in errors} == {409}
    assert _stored(firestore_client, uid, session_id)["lookupsUsed"] == exercise.lookup_limit
