from tests.fakes import make_client


def test_health_returns_ok() -> None:
    response = make_client().get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": "0.1.0", "env": "test"}


def test_health_needs_no_token_even_when_app_check_is_enforced() -> None:
    response = make_client(app_check_mode="enforce").get("/v1/health")

    assert response.status_code == 200


def test_cors_allows_configured_origin() -> None:
    response = make_client().get("/v1/health", headers={"Origin": "http://localhost:3000"})

    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"


def test_cors_rejects_unknown_origin() -> None:
    response = make_client().get("/v1/health", headers={"Origin": "https://evil.example"})

    assert "access-control-allow-origin" not in response.headers
