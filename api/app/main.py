"""Application factory.

uvicorn runs ``app.main:build_app`` with ``--factory``, so nothing (settings, Firebase,
logging) is initialized at import time. Tests call ``create_app`` with a fake verifier,
an in-memory repo, a fixed clock, a fake model, fake speech and a fake search answerer.
"""

import firebase_admin
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.ai import JsonGenerator, SearchAnswerer, UnconfiguredAnswerer, UnconfiguredGenerator
from app.ai.gemini import (
    GROUNDED_LEARNER_TIMEOUT_SECONDS,
    LEARNER_TIMEOUT_SECONDS,
    GeminiGroundedWriter,
    GeminiJsonGenerator,
    vertex_models,
)
from app.ai.speech import mascot_voices, tts_client
from app.auth import TokenVerifier, current_user
from app.clock import Clock, system_clock
from app.config import Settings, load_settings
from app.errors import drop_default_validation_docs, install_error_handlers
from app.firebase import FirebaseTokenVerifier, initialize_firebase_app, load_default_credentials
from app.logs import RequestLogMiddleware, configure_logging
from app.repo import LearningRepo
from app.repo.firestore import FirestoreLearningRepo, emulator_firestore_client, firestore_client
from app.routers import answers, health, lessons, live_checks, prompt, tts
from app.services.feedback_audio import FEEDBACK_AUDIO_PREFIX, FeedbackSpeech, UnconfiguredSpeech
from app.speech_cache import CachedSpeech
from app.storage import BucketAudioStore, firebase_bucket

API_VERSION = "0.1.0"

# Every /v1 router except health requires a verified caller (and App Check when enforced).
PROTECTED_ROUTERS = (answers, prompt, tts, lessons, live_checks)


def create_app(
    settings: Settings,
    token_verifier: TokenVerifier,
    repo: LearningRepo,
    clock: Clock,
    generator: JsonGenerator,
    speech: FeedbackSpeech,
    # Live checks (Q10). Unconfigured by default, like AI being off.
    answerer: SearchAnswerer | None = None,
) -> FastAPI:
    app = FastAPI(title="ailearn API", version=API_VERSION)
    app.state.settings = settings
    app.state.token_verifier = token_verifier
    app.state.repo = repo
    app.state.clock = clock
    app.state.generator = generator
    app.state.speech = speech
    app.state.answerer = answerer or UnconfiguredAnswerer()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type", "X-Firebase-AppCheck"],
    )
    # Added last so it is outermost and also logs CORS preflights.
    app.add_middleware(RequestLogMiddleware, project_id=settings.firebase_project_id)
    install_error_handlers(app)
    app.include_router(health.router)
    for module in PROTECTED_ROUTERS:
        app.include_router(module.router, dependencies=[Depends(current_user)])
    drop_default_validation_docs(app)
    return app


def build_app() -> FastAPI:
    settings = load_settings()
    configure_logging()
    firebase_app = initialize_firebase_app(settings.firebase_project_id)
    # Only emulator ID tokens with App Check disabled (local compose) verify without credentials.
    if settings.app_check_mode == "enforce" or settings.firebase_auth_emulator_host is None:
        load_default_credentials(firebase_app)
    if settings.firestore_emulator_host is None:
        client = firestore_client(firebase_app)
    else:
        client = emulator_firestore_client(firebase_app)
    repo = FirestoreLearningRepo(client)
    return create_app(
        settings,
        FirebaseTokenVerifier(firebase_app),
        repo,
        system_clock,
        build_generator(settings),
        build_speech(settings, firebase_app),
        build_answerer(settings),
    )


def build_generator(settings: Settings) -> JsonGenerator:
    if settings.gemini_model is None or settings.vertex_project is None:
        return UnconfiguredGenerator()
    models = vertex_models(
        settings.vertex_project, settings.vertex_location, LEARNER_TIMEOUT_SECONDS
    )
    return GeminiJsonGenerator(models, settings.gemini_model)


def build_answerer(settings: Settings) -> SearchAnswerer:
    if settings.gemini_model is None or settings.vertex_project is None:
        return UnconfiguredAnswerer()
    models = vertex_models(
        settings.vertex_project, settings.vertex_location, GROUNDED_LEARNER_TIMEOUT_SECONDS
    )
    return GeminiGroundedWriter(models, settings.gemini_model)


def build_speech(settings: Settings, firebase_app: firebase_admin.App) -> FeedbackSpeech:
    if settings.tts_model is None or settings.storage_bucket is None:
        return UnconfiguredSpeech()
    voices = mascot_voices(tts_client(), settings.tts_model, settings.tts_voice)
    store = BucketAudioStore(firebase_bucket(firebase_app, settings.storage_bucket))
    return CachedSpeech(store, voices, FEEDBACK_AUDIO_PREFIX)
