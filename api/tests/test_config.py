import pytest
from pydantic import ValidationError

from app.config import Settings


def test_cors_origins_are_split_from_comma_separated_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:3000, https://ailearn.web.app")

    assert Settings().cors_origins == ("http://localhost:3000", "https://ailearn.web.app")


def test_invalid_app_env_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "staging")

    with pytest.raises(ValidationError):
        Settings()


@pytest.mark.parametrize("origins", ["", "*", "http://localhost:3000,*"])
def test_empty_or_wildcard_cors_origins_are_rejected(
    monkeypatch: pytest.MonkeyPatch, origins: str
) -> None:
    monkeypatch.setenv("CORS_ORIGINS", origins)

    with pytest.raises(ValidationError):
        Settings()


def test_app_check_is_enforced_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("APP_CHECK_MODE", raising=False)

    assert Settings().app_check_mode == "enforce"


def test_invalid_app_check_mode_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_CHECK_MODE", "off")

    with pytest.raises(ValidationError):
        Settings()


def test_prod_with_app_check_disabled_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "disabled")

    with pytest.raises(ValidationError, match="APP_CHECK_MODE must be 'enforce'"):
        Settings()


def test_prod_with_auth_emulator_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "firebase:9099")

    with pytest.raises(ValidationError, match="FIREBASE_AUTH_EMULATOR_HOST"):
        Settings()


def _set_vertex(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GEMINI_MODEL", "test-model")
    monkeypatch.setenv("VERTEX_PROJECT", "test-project")
    monkeypatch.setenv("TTS_MODEL", "test-tts-model")
    monkeypatch.setenv("STORAGE_BUCKET", "test-bucket")


def test_empty_emulator_host_counts_as_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    _set_vertex(monkeypatch)
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "")
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "")

    settings = Settings()

    assert settings.firebase_auth_emulator_host is None
    assert settings.firestore_emulator_host is None


def test_prod_with_firestore_emulator_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "firebase:8080")

    with pytest.raises(ValidationError, match="FIRESTORE_EMULATOR_HOST"):
        Settings()


def test_prod_with_app_check_enforced_starts(monkeypatch: pytest.MonkeyPatch) -> None:
    _set_vertex(monkeypatch)
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")

    assert Settings().app_check_mode == "enforce"


def test_local_may_disable_app_check_and_use_the_emulator(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("APP_CHECK_MODE", "disabled")
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "firebase:9099")

    assert Settings().app_check_mode == "disabled"


def test_prod_without_gemini_model_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("GEMINI_MODEL", raising=False)
    monkeypatch.delenv("VERTEX_PROJECT", raising=False)
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")

    with pytest.raises(ValidationError, match="GEMINI_MODEL and VERTEX_PROJECT must be set"):
        Settings()


@pytest.mark.parametrize(
    ("model", "project"), [("test-model", ""), ("", "test-project")], ids=["model", "project"]
)
def test_gemini_model_and_vertex_project_go_together(
    monkeypatch: pytest.MonkeyPatch, model: str, project: str
) -> None:
    monkeypatch.setenv("GEMINI_MODEL", model)
    monkeypatch.setenv("VERTEX_PROJECT", project)

    with pytest.raises(ValidationError, match="must be set together"):
        Settings()


def test_local_without_gemini_turns_ai_off(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "local")
    # compose passes empty values when GEMINI_MODEL / VERTEX_PROJECT are not configured
    monkeypatch.setenv("GEMINI_MODEL", "")
    monkeypatch.setenv("VERTEX_PROJECT", "")

    settings = Settings()

    assert (settings.gemini_model, settings.vertex_project) == (None, None)
    assert settings.vertex_location == "global"


def test_prod_without_tts_model_stops_startup(monkeypatch: pytest.MonkeyPatch) -> None:
    _set_vertex(monkeypatch)
    monkeypatch.delenv("FIREBASE_AUTH_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    monkeypatch.delenv("TTS_MODEL")
    monkeypatch.delenv("STORAGE_BUCKET")
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("APP_CHECK_MODE", "enforce")

    with pytest.raises(ValidationError, match="TTS_MODEL and STORAGE_BUCKET must be set"):
        Settings()


@pytest.mark.parametrize(
    ("model", "bucket"), [("test-tts-model", ""), ("", "test-bucket")], ids=["model", "bucket"]
)
def test_tts_model_and_storage_bucket_go_together(
    monkeypatch: pytest.MonkeyPatch, model: str, bucket: str
) -> None:
    monkeypatch.setenv("TTS_MODEL", model)
    monkeypatch.setenv("STORAGE_BUCKET", bucket)

    with pytest.raises(ValidationError, match="must be set together"):
        Settings()


def test_live_check_daily_limit_defaults_to_ten_and_reads_the_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("LIVE_CHECK_DAILY_LIMIT", raising=False)
    assert Settings().live_check_daily_limit == 10

    monkeypatch.setenv("LIVE_CHECK_DAILY_LIMIT", "3")
    assert Settings().live_check_daily_limit == 3


@pytest.mark.parametrize("value", ["0", "-1", "abc"])
def test_invalid_live_check_daily_limit_stops_startup(
    monkeypatch: pytest.MonkeyPatch, value: str
) -> None:
    monkeypatch.setenv("LIVE_CHECK_DAILY_LIMIT", value)
    with pytest.raises(ValidationError):
        Settings()
