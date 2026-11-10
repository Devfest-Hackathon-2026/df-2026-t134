from fastapi.testclient import TestClient

from app.errors import not_implemented
from tests.fakes import AUTH_HEADERS, FakeTokenVerifier, make_app, make_client

client = make_client()


def test_unexpected_error_returns_internal_error_body() -> None:
    app = make_app("disabled", FakeTokenVerifier())

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("secret detail")

    response = TestClient(app, raise_server_exceptions=False).get("/boom")

    assert response.status_code == 500
    assert response.json() == {"error": {"code": "internal", "message": "Internal server error"}}


def test_unimplemented_endpoint_returns_error_body() -> None:
    app = make_app("disabled", FakeTokenVerifier())

    @app.post("/v1/planned")
    def planned() -> None:
        raise not_implemented("PR-99")

    response = TestClient(app).post("/v1/planned", headers=AUTH_HEADERS)

    assert response.status_code == 501
    assert response.json() == {
        "error": {"code": "not_implemented", "message": "Not implemented yet (planned in PR-99)"}
    }


def test_invalid_body_returns_bad_request() -> None:
    response = client.post("/v1/answers", json={"exerciseId": "U1"}, headers=AUTH_HEADERS)

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


def test_unknown_route_returns_not_found() -> None:
    response = client.get("/v1/unknown")

    assert response.status_code == 404
    assert response.json() == {"error": {"code": "not_found", "message": "Not Found"}}
