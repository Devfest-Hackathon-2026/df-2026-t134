import pytest
from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient

from app.auth import CurrentUserDep, current_user
from tests.fakes import (
    AUTH_HEADERS,
    LEARNER,
    VALID_APP_CHECK_TOKEN,
    VALID_ID_TOKEN,
    FakeTokenVerifier,
    make_app,
    make_client,
)

ANSWER = {"exerciseId": "u1-l1-q1", "answer": {"type": "choice", "optionId": "a"}}

# The app under test has no content, so authenticated learning requests answer 404.
REACHED_HANDLER = 404

# (route template, concrete URL, valid body, status once authenticated) per protected
# endpoint; the set of route templates is checked against the app below, so a new
# unprotected router fails the suite.
PROTECTED_REQUESTS = [
    ("/v1/answers", "/v1/answers", ANSWER, REACHED_HANDLER),
    (
        "/v1/prompt/evaluate",
        "/v1/prompt/evaluate",
        {"exerciseId": "u1-l1-q1", "prompt": "hello"},
        REACHED_HANDLER,
    ),
    ("/v1/tts", "/v1/tts", {"attemptId": "a1"}, REACHED_HANDLER),
    ("/v1/lessons/{lesson_id}/complete", "/v1/lessons/u1-l1/complete", None, REACHED_HANDLER),
    (
        "/v1/live-checks",
        "/v1/live-checks",
        {"exerciseId": "u3-l1-q1", "prompt": "hi"},
        REACHED_HANDLER,
    ),
    (
        "/v1/live-checks/{session_id}/lookup",
        "/v1/live-checks/s1/lookup",
        {"sentenceIndex": 0},
        REACHED_HANDLER,
    ),
]
PROTECTED_ROUTES = {route for route, _, _, _ in PROTECTED_REQUESTS}


def _post(client: TestClient, headers: dict[str, str]) -> dict[str, object]:
    response = client.post("/v1/answers", json=ANSWER, headers=headers)
    assert response.status_code == 401
    body = response.json()
    assert body["error"]["code"] == "unauthenticated"
    return body


def test_valid_token_reaches_the_handler() -> None:
    response = make_client().post("/v1/answers", json=ANSWER, headers=AUTH_HEADERS)

    assert response.status_code == REACHED_HANDLER


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"Authorization": ""},
        {"Authorization": "Bearer"},
        {"Authorization": f"Basic {VALID_ID_TOKEN}"},
        {"Authorization": VALID_ID_TOKEN},
    ],
    ids=["missing", "empty", "no-token", "wrong-scheme", "no-scheme"],
)
def test_missing_or_malformed_authorization_is_rejected(headers: dict[str, str]) -> None:
    verifier = FakeTokenVerifier()

    _post(TestClient(make_app("disabled", verifier)), headers)

    assert verifier.id_tokens == []


def test_invalid_token_is_rejected_without_echoing_it() -> None:
    body = _post(make_client(), {"Authorization": "Bearer forged-token"})

    assert "forged-token" not in str(body)


def test_bearer_scheme_is_case_insensitive() -> None:
    response = make_client().post(
        "/v1/answers", json=ANSWER, headers={"Authorization": f"bearer {VALID_ID_TOKEN}"}
    )

    assert response.status_code == REACHED_HANDLER


def test_authentication_runs_before_body_validation() -> None:
    response = make_client().post("/v1/answers", json={"exerciseId": "U1"})

    assert response.status_code == 401


@pytest.mark.parametrize(("route", "url", "body", "status"), PROTECTED_REQUESTS)
def test_every_protected_endpoint_requires_a_token(
    route: str, url: str, body: object, status: int
) -> None:
    client = make_client()

    assert client.post(url, json=body).status_code == 401
    assert client.post(url, json=body, headers=AUTH_HEADERS).status_code == status


def test_every_v1_route_except_health_is_listed_as_protected() -> None:
    paths = set(make_app("disabled", FakeTokenVerifier()).openapi()["paths"])

    assert paths - {"/v1/health"} == PROTECTED_ROUTES


def test_app_check_disabled_ignores_the_header() -> None:
    verifier = FakeTokenVerifier()
    client = TestClient(make_app("disabled", verifier))

    response = client.post("/v1/answers", json=ANSWER, headers=AUTH_HEADERS)

    assert response.status_code == REACHED_HANDLER
    assert verifier.app_check_tokens == []


@pytest.mark.parametrize(
    "app_check_headers",
    [{}, {"X-Firebase-AppCheck": ""}, {"X-Firebase-AppCheck": "forged-app-check"}],
    ids=["missing", "empty", "invalid"],
)
def test_app_check_enforced_rejects_missing_or_invalid_token(
    app_check_headers: dict[str, str],
) -> None:
    body = _post(make_client("enforce"), {**AUTH_HEADERS, **app_check_headers})

    assert "forged-app-check" not in str(body)


def test_app_check_enforced_accepts_valid_token() -> None:
    headers = {**AUTH_HEADERS, "X-Firebase-AppCheck": VALID_APP_CHECK_TOKEN}

    response = make_client("enforce").post("/v1/answers", json=ANSWER, headers=headers)

    assert response.status_code == REACHED_HANDLER


def test_app_check_enforced_still_requires_id_token() -> None:
    _post(make_client("enforce"), {"X-Firebase-AppCheck": VALID_APP_CHECK_TOKEN})


def test_handler_receives_current_user_and_tokens_are_verified_once() -> None:
    verifier = FakeTokenVerifier()
    app = make_app("enforce", verifier)
    router = APIRouter()

    @router.get("/v1/whoami")
    def whoami(user: CurrentUserDep) -> dict[str, object]:
        return {"uid": user.uid, "isAnonymous": user.is_anonymous}

    # Same wiring as create_app: router-level dependency plus the handler's own parameter.
    app.include_router(router, dependencies=[Depends(current_user)])
    headers = {**AUTH_HEADERS, "X-Firebase-AppCheck": VALID_APP_CHECK_TOKEN}

    response = TestClient(app).get("/v1/whoami", headers=headers)

    assert response.json() == {"uid": LEARNER.uid, "isAnonymous": True}
    assert verifier.id_tokens == [VALID_ID_TOKEN]
    assert verifier.app_check_tokens == [VALID_APP_CHECK_TOKEN]


def test_openapi_declares_bearer_security_on_protected_operations() -> None:
    schema = make_app("disabled", FakeTokenVerifier()).openapi()

    scheme = schema["components"]["securitySchemes"]["FirebaseIdToken"]
    assert scheme["type"] == "http"
    assert scheme["scheme"] == "bearer"
    assert "security" not in schema["paths"]["/v1/health"]["get"]
    for route in PROTECTED_ROUTES:
        operation = schema["paths"][route]["post"]
        assert operation["security"] == [{"FirebaseIdToken": []}]
        assert "X-Firebase-AppCheck" in {p["name"] for p in operation["parameters"]}
