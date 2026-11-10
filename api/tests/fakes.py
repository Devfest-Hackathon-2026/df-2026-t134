"""Test doubles and helpers shared by the API tests (no network, no Firebase)."""

import datetime as dt

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.ai import GenerationRequest, GroundedText, JsonGenerator, UnconfiguredGenerator
from app.auth import CurrentUser
from app.clock import Clock
from app.config import AppCheckMode, Settings
from app.main import create_app
from app.repo import LearningRepo
from app.repo.memory import InMemoryLearningRepo
from app.services.feedback_audio import FeedbackSpeech, UnconfiguredSpeech

VALID_ID_TOKEN = "valid-id-token"
VALID_APP_CHECK_TOKEN = "valid-app-check-token"
LEARNER = CurrentUser(uid="learner-1", sign_in_provider="anonymous")

AUTH_HEADERS = {"Authorization": f"Bearer {VALID_ID_TOKEN}"}


class FakeTokenVerifier:
    """Accepts exactly one ID token and one App Check token; records what it was asked."""

    def __init__(self) -> None:
        self.id_tokens: list[str] = []
        self.app_check_tokens: list[str] = []

    def verify_id_token(self, id_token: str) -> CurrentUser | None:
        self.id_tokens.append(id_token)
        return LEARNER if id_token == VALID_ID_TOKEN else None

    def verify_app_check_token(self, app_check_token: str) -> bool:
        self.app_check_tokens.append(app_check_token)
        return app_check_token == VALID_APP_CHECK_TOKEN


def make_settings(app_check_mode: AppCheckMode = "disabled") -> Settings:
    # Explicit values so the tests do not depend on the container's environment.
    return Settings(
        app_env="test",
        app_check_mode=app_check_mode,
        firebase_project_id="demo-ailearn",
        cors_origins=("http://localhost:3000",),
        firebase_auth_emulator_host=None,
        firestore_emulator_host=None,
        gemini_model=None,
        vertex_project=None,
        tts_model=None,
        storage_bucket=None,
    )


class FakeGenerator:
    """Returns the queued outputs in order (an exception is raised instead) and records requests."""

    def __init__(self, *outputs: BaseModel | Exception) -> None:
        self.outputs = list(outputs)
        self.requests: list[GenerationRequest] = []

    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        self.requests.append(request)
        output = self.outputs.pop(0)
        if isinstance(output, Exception):
            raise output
        if not isinstance(output, schema):
            raise TypeError(f"queued {type(output).__name__}, asked for {schema.__name__}")
        return output


class FakeAnswerer:
    """A SearchAnswerer that returns the queued grounded answers in order (an exception is
    raised instead) and records requests."""

    def __init__(self, *outputs: GroundedText | Exception) -> None:
        self.outputs = list(outputs)
        self.requests: list[GenerationRequest] = []

    def answer(self, request: GenerationRequest) -> GroundedText:
        self.requests.append(request)
        output = self.outputs.pop(0)
        if isinstance(output, Exception):
            raise output
        return output


# The tests that do not reach a model or speak run with AI turned off, as in local development.
NO_AI = UnconfiguredGenerator()
NO_SPEECH = UnconfiguredSpeech()


# Monday 2026-11-09, 10:00 in Asia/Tokyo.
NOW = dt.datetime(2026, 11, 9, 1, 0, tzinfo=dt.UTC)


def fixed_clock(now: dt.datetime) -> Clock:
    return lambda: now


def make_app(app_check_mode: AppCheckMode, verifier: FakeTokenVerifier) -> FastAPI:
    """App without content: protected learning endpoints answer 404."""
    return create_app(
        make_settings(app_check_mode),
        verifier,
        InMemoryLearningRepo(),
        fixed_clock(NOW),
        NO_AI,
        NO_SPEECH,
    )


def make_client(app_check_mode: AppCheckMode = "disabled") -> TestClient:
    return TestClient(make_app(app_check_mode, FakeTokenVerifier()))


def make_learning_client(
    repo: LearningRepo,
    clock: Clock,
    generator: JsonGenerator = NO_AI,
    speech: FeedbackSpeech = NO_SPEECH,
) -> TestClient:
    """Signed-in learner (send AUTH_HEADERS) against the given data, time, model and speech."""
    app = create_app(make_settings(), FakeTokenVerifier(), repo, clock, generator, speech)
    return TestClient(app)
