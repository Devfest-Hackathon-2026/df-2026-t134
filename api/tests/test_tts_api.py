"""POST /v1/tts with the in-memory repo, a fake bucket and fake voices."""

import io
import logging
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.ai import AiUnavailable
from app.logs import JsonFormatter
from app.repo.memory import InMemoryLearningRepo
from app.services.feedback_audio import FEEDBACK_AUDIO_PREFIX
from app.speech_cache import CachedSpeech, audio_path
from tests.content import ANSWER_KEYS, CHOICE_ID, CORRECT_ANSWERS, WRONG_ANSWERS, make_repo
from tests.fakes import AUTH_HEADERS, LEARNER, NOW, fixed_clock, make_learning_client

EXPLANATION = ANSWER_KEYS[CHOICE_ID].explanation  # type: ignore[union-attr]


class FakeStore:
    def __init__(self) -> None:
        self.files: dict[str, tuple[bytes, str]] = {}

    def exists(self, path: str) -> bool:
        return path in self.files

    def put(self, path: str, data: bytes, content_type: str) -> None:
        self.files[path] = (data, content_type)


class FakeVoice:
    """Speaks every text as b"<voice_id>:<text>", or always fails; records what it spoke."""

    def __init__(self, voice_id: str, *, fails: bool = False) -> None:
        self.voice_id = voice_id
        self.fails = fails
        self.spoken: list[str] = []

    def synthesize(self, text: str) -> bytes:
        self.spoken.append(text)
        if self.fails:
            raise AiUnavailable(f"{self.voice_id} is down")
        return f"{self.voice_id}:{text}".encode()


@pytest.fixture
def repo() -> InMemoryLearningRepo:
    return make_repo()


@pytest.fixture
def store() -> FakeStore:
    return FakeStore()


def _client(repo: InMemoryLearningRepo, store: FakeStore, *voices: FakeVoice) -> TestClient:
    speech = CachedSpeech(store, voices, FEEDBACK_AUDIO_PREFIX)
    return make_learning_client(repo, fixed_clock(NOW), speech=speech)


def _feedback_path(voice_id: str) -> str:
    return audio_path(FEEDBACK_AUDIO_PREFIX, voice_id, EXPLANATION)


def _answer(client: TestClient, answer: dict[str, Any]) -> str:
    response = client.post(
        "/v1/answers", json={"exerciseId": CHOICE_ID, "answer": answer}, headers=AUTH_HEADERS
    )
    assert response.status_code == 200
    return response.json()["attemptId"]


def _tts(client: TestClient, attempt_id: str) -> Any:
    return client.post("/v1/tts", json={"attemptId": attempt_id}, headers=AUTH_HEADERS)


def test_feedback_is_spoken_by_the_mascot_and_stored(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    mascot = FakeVoice("mascot")
    client = _client(repo, store, mascot, FakeVoice("fallback"))

    response = _tts(client, _answer(client, CORRECT_ANSWERS[CHOICE_ID]))

    assert response.status_code == 200
    path = response.json()["storagePath"]
    assert path == _feedback_path("mascot")
    assert path.startswith(FEEDBACK_AUDIO_PREFIX) and path.endswith(".mp3")
    assert store.files[path] == (f"mascot:{EXPLANATION}".encode(), "audio/mpeg")
    assert mascot.spoken == [EXPLANATION]


def test_same_text_the_second_time_comes_from_the_cache(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    mascot = FakeVoice("mascot")
    client = _client(repo, store, mascot)
    # Two attempts at one exercise share its explanation (as every learner does).
    wrong, right = (
        _answer(client, WRONG_ANSWERS[CHOICE_ID]),
        _answer(client, CORRECT_ANSWERS[CHOICE_ID]),
    )

    first, again, second = _tts(client, wrong), _tts(client, wrong), _tts(client, right)

    assert first.json() == again.json() == second.json()
    assert mascot.spoken == [EXPLANATION]
    assert len(store.files) == 1


def test_fallback_voice_speaks_while_the_mascot_is_down(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    fallback = FakeVoice("fallback")
    client = _client(repo, store, FakeVoice("mascot", fails=True), fallback)

    response = _tts(client, _answer(client, CORRECT_ANSWERS[CHOICE_ID]))

    assert response.json()["storagePath"] == _feedback_path("fallback")
    assert fallback.spoken == [EXPLANATION]


def test_mascot_voice_replaces_the_fallback_once_it_is_back(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    down = _client(repo, store, FakeVoice("mascot", fails=True), FakeVoice("fallback"))
    attempt_id = _answer(down, CORRECT_ANSWERS[CHOICE_ID])
    _tts(down, attempt_id)

    back = _client(repo, store, FakeVoice("mascot"), FakeVoice("fallback"))

    assert _tts(back, attempt_id).json()["storagePath"] == _feedback_path("mascot")


def test_no_voice_available_answers_503_and_stores_nothing(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    client = _client(repo, store, FakeVoice("mascot", fails=True), FakeVoice("fb", fails=True))

    response = _tts(client, _answer(client, CORRECT_ANSWERS[CHOICE_ID]))

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "upstream_unavailable"
    assert store.files == {}


def test_without_tts_settings_the_endpoint_answers_503(repo: InMemoryLearningRepo) -> None:
    client = make_learning_client(repo, fixed_clock(NOW))  # speech turned off, as in local dev

    response = _tts(client, _answer(client, CORRECT_ANSWERS[CHOICE_ID]))

    assert response.status_code == 503


def test_attempts_of_other_learners_are_not_found(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    mascot = FakeVoice("mascot")
    client = _client(repo, store, mascot)
    attempt_id = _answer(client, CORRECT_ANSWERS[CHOICE_ID])
    # Hand the attempt to another learner: the caller now asks for an id that is not theirs.
    repo.attempts["someone-else"] = repo.attempts.pop(LEARNER.uid)

    responses = [_tts(client, attempt_id), _tts(client, "unknown-attempt")]

    assert [r.status_code for r in responses] == [404, 404]
    assert mascot.spoken == []


def test_request_with_text_instead_of_an_attempt_is_rejected(
    repo: InMemoryLearningRepo, store: FakeStore
) -> None:
    client = _client(repo, store, FakeVoice("mascot"))

    response = client.post(
        "/v1/tts", json={"attemptId": "a1", "text": "なんでも読ませる"}, headers=AUTH_HEADERS
    )

    assert response.status_code == 400


@pytest.fixture
def captured() -> Iterator[io.StringIO]:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("app")
    logger.addHandler(handler)
    previous = logger.level
    logger.setLevel(logging.INFO)
    yield stream
    logger.removeHandler(handler)
    logger.setLevel(previous)


def test_logs_never_contain_the_feedback_text(
    repo: InMemoryLearningRepo, store: FakeStore, captured: io.StringIO
) -> None:
    client = _client(repo, store, FakeVoice("mascot", fails=True), FakeVoice("fb", fails=True))

    _tts(client, _answer(client, CORRECT_ANSWERS[CHOICE_ID]))

    raw = captured.getvalue()
    assert "voice unavailable" in raw
    assert EXPLANATION.splitlines()[0] not in raw
