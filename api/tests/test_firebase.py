"""FirebaseTokenVerifier against the real Admin SDK, offline (Auth emulator mode, no key fetch)."""

import time
import uuid
from collections.abc import Iterator

import firebase_admin
import jwt
import pytest
from firebase_admin import credentials
from google.auth.credentials import AnonymousCredentials

from app.auth import CurrentUser
from app.firebase import FirebaseTokenVerifier

PROJECT_ID = "demo-ailearn"


class _OfflineCredential(credentials.Base):
    def get_credential(self) -> AnonymousCredentials:
        return AnonymousCredentials()


@pytest.fixture
def verifier(monkeypatch: pytest.MonkeyPatch) -> Iterator[FirebaseTokenVerifier]:
    # Emulator mode: the SDK accepts unsigned tokens, so nothing is fetched from Google.
    monkeypatch.setenv("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099")
    app = firebase_admin.initialize_app(
        _OfflineCredential(), options={"projectId": PROJECT_ID}, name=f"test-{uuid.uuid4()}"
    )
    yield FirebaseTokenVerifier(app)
    firebase_admin.delete_app(app)


def _emulator_token(*, provider: str = "anonymous", aud: str = PROJECT_ID) -> str:
    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{aud}",
        "aud": aud,
        "sub": "uid-123",
        "iat": now - 10,
        "auth_time": now - 10,
        "exp": now + 3600,
        "firebase": {"sign_in_provider": provider, "identities": {}},
    }
    return jwt.encode(claims, key=None, algorithm="none")


def test_emulator_token_yields_current_user(verifier: FirebaseTokenVerifier) -> None:
    user = verifier.verify_id_token(_emulator_token())

    assert user == CurrentUser(uid="uid-123", sign_in_provider="anonymous")
    assert user.is_anonymous


def test_non_anonymous_provider_is_reported(verifier: FirebaseTokenVerifier) -> None:
    user = verifier.verify_id_token(_emulator_token(provider="google.com"))

    assert user is not None
    assert not user.is_anonymous


# Expiry and signatures are not checked in emulator mode (google-auth does it in production),
# so only the claim checks the SDK always applies are exercised here.
@pytest.mark.parametrize(
    "token",
    ["not-a-jwt", _emulator_token(aud="another-project")],
    ids=["malformed", "other-project"],
)
def test_invalid_id_tokens_are_rejected(verifier: FirebaseTokenVerifier, token: str) -> None:
    assert verifier.verify_id_token(token) is None


def test_malformed_app_check_token_is_rejected(verifier: FirebaseTokenVerifier) -> None:
    assert verifier.verify_app_check_token("not-a-jwt") is False
