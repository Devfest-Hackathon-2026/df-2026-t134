"""The only module that talks to the Firebase Admin SDK for authentication.

The Admin SDK App is created once by the application factory (``app.main.build_app``)
and passed to the wrappers that need it. When FIREBASE_AUTH_EMULATOR_HOST is set, the SDK
accepts the Auth emulator's unsigned tokens; Settings refuses that combination in prod.
"""

import firebase_admin
import jwt
from firebase_admin import app_check, auth

from app.auth import CurrentUser
from app.errors import ApiError


def initialize_firebase_app(project_id: str) -> firebase_admin.App:
    """Create the Admin SDK app. Credentials are Application Default Credentials, loaded lazily
    (Cloud Run service account in production; not needed for ID tokens on the emulator)."""
    return firebase_admin.initialize_app(options={"projectId": project_id})


def load_default_credentials(firebase_app: firebase_admin.App) -> None:
    """Resolve Application Default Credentials now (raises DefaultCredentialsError if absent).

    The SDK needs them to verify real ID tokens and any App Check token, but would otherwise
    look them up on the first request and fail every request after a misconfigured deploy.
    """
    firebase_app.credential.get_credential()


def _verification_unavailable() -> ApiError:
    return ApiError(503, "upstream_unavailable", "Token verification is temporarily unavailable")


class FirebaseTokenVerifier:
    """TokenVerifier backed by firebase_admin.auth and firebase_admin.app_check."""

    def __init__(self, firebase_app: firebase_admin.App) -> None:
        self._app = firebase_app

    def verify_id_token(self, id_token: str) -> CurrentUser | None:
        try:
            claims = auth.verify_id_token(id_token, app=self._app)
        except auth.CertificateFetchError as exc:
            raise _verification_unavailable() from exc
        # ValueError: malformed. InvalidIdTokenError covers expired / revoked / wrong project.
        except (ValueError, auth.InvalidIdTokenError):
            return None
        provider = claims["firebase"]["sign_in_provider"]
        return CurrentUser(uid=claims["uid"], sign_in_provider=provider)

    def verify_app_check_token(self, app_check_token: str) -> bool:
        try:
            app_check.verify_token(app_check_token, app=self._app)
        except jwt.PyJWKClientConnectionError as exc:
            raise _verification_unavailable() from exc
        # ValueError: malformed / bad signature / expired / wrong project.
        # PyJWKClientError: the token names a signing key that App Check does not publish.
        except (ValueError, jwt.PyJWKClientError):
            return False
        return True
