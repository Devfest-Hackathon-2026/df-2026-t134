import io
import json
import logging
import sys
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.logs import TRACE_FIELD, JsonFormatter, trace_resource
from tests.fakes import AUTH_HEADERS, VALID_ID_TOKEN, make_client

TRACE_ID = "105445aa7843bc8bf206b12000100000"


@pytest.fixture
def captured() -> Iterator[io.StringIO]:
    """Capture what the request logger writes, formatted exactly as on Cloud Run."""
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("app.requests")
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    yield stream
    logger.removeHandler(handler)


def _lines(stream: io.StringIO) -> list[dict[str, object]]:
    return [json.loads(line) for line in stream.getvalue().splitlines()]


def test_request_log_is_one_json_line_with_http_request_fields(captured: io.StringIO) -> None:
    make_client().get("/v1/health?debug=1")

    [line] = _lines(captured)
    assert line["severity"] == "INFO"
    assert line["message"] == "GET /v1/health 200"
    http = line["httpRequest"]
    assert isinstance(http, dict)
    assert http["requestMethod"] == "GET"
    assert http["requestUrl"] == "/v1/health"  # query strings are not logged
    assert http["status"] == 200
    assert str(http["latency"]).endswith("s")
    assert TRACE_FIELD not in line


def test_request_log_carries_cloud_trace(captured: io.StringIO) -> None:
    make_client().get("/v1/health", headers={"X-Cloud-Trace-Context": f"{TRACE_ID}/1;o=1"})

    [line] = _lines(captured)
    assert line[TRACE_FIELD] == f"projects/demo-ailearn/traces/{TRACE_ID}"


def test_request_log_never_contains_tokens_or_bodies(captured: io.StringIO) -> None:
    client: TestClient = make_client()
    secret_prompt = "my-name-is-taro-yamada"
    client.post(
        "/v1/prompt/evaluate",
        json={"exerciseId": "u1-l1-q1", "prompt": secret_prompt},
        headers={**AUTH_HEADERS, "X-Firebase-AppCheck": "app-check-secret"},
    )
    client.post("/v1/answers", json={}, headers={"Authorization": "Bearer forged-token"})

    raw = captured.getvalue()
    for secret in (VALID_ID_TOKEN, "forged-token", "app-check-secret", secret_prompt):
        assert secret not in raw
    severities = [line["severity"] for line in _lines(captured)]
    assert severities == ["WARNING", "WARNING"]  # unknown exercise (404), then 401


@pytest.mark.parametrize(
    ("header", "expected"),
    [
        (None, None),
        ("", None),
        (f"{TRACE_ID}/1;o=1", f"projects/p/traces/{TRACE_ID}"),
        (TRACE_ID.upper(), f"projects/p/traces/{TRACE_ID}"),
        ("not-a-trace/1", None),
        ('"},"injected":"x', None),
    ],
)
def test_trace_resource(header: str | None, expected: str | None) -> None:
    assert trace_resource("p", header) == expected


def test_formatter_adds_structured_fields_and_exceptions() -> None:
    try:
        raise RuntimeError("boom")
    except RuntimeError:
        exc_info = sys.exc_info()
    record = logging.LogRecord("app.x", logging.ERROR, __file__, 1, "failed %s", ("x",), exc_info)
    record.json_fields = {"lessonId": "u1-l1"}

    line = json.loads(JsonFormatter().format(record))

    assert line["severity"] == "ERROR"
    assert line["message"].startswith("failed x\nTraceback")
    assert line["lessonId"] == "u1-l1"
