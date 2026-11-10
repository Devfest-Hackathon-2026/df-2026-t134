"""Application settings loaded from environment variables.

Settings are validated once at startup; invalid values stop the process
instead of falling back to defaults.
"""

from typing import Annotated, Literal, Self

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

from app.mascot import DEFAULT_VOICE

AppEnv = Literal["local", "test", "prod"]

# "enforce": every protected request must carry a valid X-Firebase-AppCheck token.
# "disabled": the header is ignored (local emulators only; rejected when APP_ENV=prod).
AppCheckMode = Literal["enforce", "disabled"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", frozen=True)

    app_env: AppEnv = "local"
    firebase_project_id: str = Field(default="demo-ailearn", min_length=1)
    # Comma-separated list in the environment, e.g. "http://localhost:3000,https://example.web.app"
    cors_origins: Annotated[tuple[str, ...], NoDecode] = ("http://localhost:3000",)
    app_check_mode: AppCheckMode = "enforce"
    # Read here only to refuse a production start that would trust unsigned emulator tokens.
    # The Admin SDK itself reads the same variable to switch to the Auth emulator.
    firebase_auth_emulator_host: str | None = None
    # When set, the Firestore client talks to the emulator without Google credentials
    # (the client library reads the same variable). Refused when APP_ENV=prod.
    firestore_emulator_host: str | None = None
    # Gemini on Vertex AI. The model ID is set only here, from the environment (never in code).
    # Both unset: AI endpoints answer 503 (local development without Google Cloud). Required
    # when APP_ENV=prod. Credentials come from the service account (ADC), never an API key.
    gemini_model: str | None = None
    vertex_project: str | None = None
    vertex_location: str = Field(default="global", min_length=1)
    # Feedback speech (Cloud Text-to-Speech). TTS_MODEL is the Gemini-TTS model ID; the
    # fallback is the Chirp 3 HD voice named TTS_VOICE. Audio is cached in STORAGE_BUCKET.
    # Both unset: POST /v1/tts answers 503. Required when APP_ENV=prod.
    tts_model: str | None = None
    tts_voice: str = Field(default=DEFAULT_VOICE, min_length=1)
    storage_bucket: str | None = None
    # Live checks (POST /v1/live-checks) a learner may start per calendar day in Asia/Tokyo.
    # Each one makes at least two Gemini calls, one of them with Google Search.
    live_check_daily_limit: int = Field(default=10, ge=1, le=100)

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return tuple(origin.strip() for origin in value.split(",") if origin.strip())
        return value

    @field_validator("cors_origins")
    @classmethod
    def _require_origins(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        if not value:
            raise ValueError("cors_origins must contain at least one origin")
        if "*" in value:
            raise ValueError("wildcard CORS origin is not allowed")
        return value

    @field_validator("firebase_auth_emulator_host", "firestore_emulator_host", mode="before")
    @classmethod
    def _empty_host_is_unset(cls, value: object) -> object:
        # The Admin SDK treats an empty *_EMULATOR_HOST as "no emulator".
        return value or None

    @field_validator("gemini_model", "vertex_project", "tts_model", "storage_bucket", mode="before")
    @classmethod
    def _empty_is_unset(cls, value: object) -> object:
        # An empty value counts as unset (`make try-prompt-grader` passes GEMINI_MODEL= when
        # it is not given).
        return value or None

    @model_validator(mode="after")
    def _require_vertex_project_with_model(self) -> Self:
        if (self.gemini_model is None) != (self.vertex_project is None):
            raise ValueError("GEMINI_MODEL and VERTEX_PROJECT must be set together")
        return self

    @model_validator(mode="after")
    def _require_bucket_with_tts_model(self) -> Self:
        if (self.tts_model is None) != (self.storage_bucket is None):
            raise ValueError("TTS_MODEL and STORAGE_BUCKET must be set together")
        return self

    @model_validator(mode="after")
    def _require_production_safeguards(self) -> Self:
        if self.app_env != "prod":
            return self
        if self.app_check_mode != "enforce":
            raise ValueError("APP_CHECK_MODE must be 'enforce' when APP_ENV=prod")
        if self.firebase_auth_emulator_host:
            raise ValueError("FIREBASE_AUTH_EMULATOR_HOST must not be set when APP_ENV=prod")
        if self.firestore_emulator_host:
            raise ValueError("FIRESTORE_EMULATOR_HOST must not be set when APP_ENV=prod")
        if self.gemini_model is None:
            raise ValueError("GEMINI_MODEL and VERTEX_PROJECT must be set when APP_ENV=prod")
        if self.tts_model is None:
            raise ValueError("TTS_MODEL and STORAGE_BUCKET must be set when APP_ENV=prod")
        return self


def load_settings() -> Settings:
    return Settings()
