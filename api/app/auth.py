"""Request authentication: Firebase ID token (always) and App Check token (when enforced).

Routers never verify tokens themselves. Protected routers are included with
``Depends(current_user)`` in ``create_app``; a handler that needs the caller declares
``user: CurrentUserDep`` (FastAPI caches the dependency, so tokens are verified once).

Failures answer 401 ``unauthenticated`` with a fixed message. Token contents and SDK
error messages (which may echo the token) are never returned or logged.
"""

from dataclasses import dataclass
from typing import Annotated, Protocol

from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings
from app.errors import ApiError

ANONYMOUS_PROVIDER = "anonymous"


@dataclass(frozen=True, slots=True)
class CurrentUser:
    """The verified caller of a request."""

    uid: str
    # Firebase "sign_in_provider" claim, e.g. "anonymous", "google.com", "password".
    sign_in_provider: str

    @property
    def is_anonymous(self) -> bool:
        return self.sign_in_provider == ANONYMOUS_PROVIDER


class TokenVerifier(Protocol):
    """Thin wrapper over the token checks of the Firebase Admin SDK (fakes in tests).

    An invalid, expired or malformed token is a normal outcome and is returned as a value.
    Implementations raise only when the check itself cannot be done (e.g. key fetch failure).
    """

    def verify_id_token(self, id_token: str) -> CurrentUser | None:
        """Return the user for a valid ID token, or None when the token is not valid."""
        ...

    def verify_app_check_token(self, app_check_token: str) -> bool:
        """Return True only for a valid App Check token of this project."""
        ...


_bearer = HTTPBearer(
    auto_error=False,
    scheme_name="FirebaseIdToken",
    bearerFormat="JWT",
    description="Firebase Authentication ID token of the signed-in (or anonymous) learner.",
)


def _unauthenticated(message: str) -> ApiError:
    return ApiError(401, "unauthenticated", message)


def require_app_check(
    request: Request,
    app_check_token: Annotated[
        str | None,
        Header(
            alias="X-Firebase-AppCheck",
            description="Firebase App Check token. Required when APP_CHECK_MODE=enforce (prod).",
        ),
    ] = None,
) -> None:
    settings: Settings = request.app.state.settings
    if settings.app_check_mode == "disabled":
        return
    verifier: TokenVerifier = request.app.state.token_verifier
    if not app_check_token or not verifier.verify_app_check_token(app_check_token):
        raise _unauthenticated("Missing or invalid App Check token")


def current_user(
    request: Request,
    _app_check: Annotated[None, Depends(require_app_check)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> CurrentUser:
    # HTTPBearer returns None for a missing header, an empty token or a non-Bearer scheme.
    if credentials is None:
        raise _unauthenticated("Missing or malformed Authorization header")
    verifier: TokenVerifier = request.app.state.token_verifier
    user = verifier.verify_id_token(credentials.credentials)
    if user is None:
        raise _unauthenticated("Invalid or expired ID token")
    return user


CurrentUserDep = Annotated[CurrentUser, Depends(current_user)]
