"""Structured logs for Cloud Run: one JSON object per line on stdout.

Cloud Logging reads ``severity``, ``message``, ``httpRequest`` and
``logging.googleapis.com/trace`` from these lines. Learners are minors: never log request
bodies, headers, tokens or anything a learner typed. Pass extra structured data with
``logger.info("...", extra={"json_fields": {...}})``.
"""

import json
import logging
import re
import sys
import time
from contextvars import ContextVar
from datetime import UTC, datetime

from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send

TRACE_FIELD = "logging.googleapis.com/trace"

# "TRACE_ID/SPAN_ID;o=OPTIONS" where TRACE_ID is 32 hex characters.
_CLOUD_TRACE_CONTEXT = re.compile(r"^([0-9a-fA-F]{32})(?:/|;|$)")

# Trace of the request being handled, so every log line inside it is grouped in Cloud Logging.
_current_trace: ContextVar[str | None] = ContextVar("current_trace", default=None)

_request_logger = logging.getLogger("app.requests")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        message = record.getMessage()
        if record.exc_info:
            message = f"{message}\n{self.formatException(record.exc_info)}"
        payload: dict[str, object] = {
            "severity": record.levelname,
            "message": message,
            "time": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "logger": record.name,
        }
        trace = _current_trace.get()
        if trace:
            payload[TRACE_FIELD] = trace
        payload.update(getattr(record, "json_fields", {}))
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging() -> None:
    """Send every log record to stdout as JSON. Call once from the application factory."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    # Route uvicorn's own messages through the JSON handler instead of its plain-text one.
    for name in ("uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
    # RequestLogMiddleware writes the access log; uvicorn's would duplicate it.
    access = logging.getLogger("uvicorn.access")
    access.handlers = []
    access.propagate = False
    access.disabled = True


def trace_resource(project_id: str, cloud_trace_context: str | None) -> str | None:
    """Turn an X-Cloud-Trace-Context header into a Cloud Logging trace resource name."""
    if not cloud_trace_context:
        return None
    match = _CLOUD_TRACE_CONTEXT.match(cloud_trace_context)
    if match is None:
        return None
    return f"projects/{project_id}/traces/{match.group(1).lower()}"


def _severity(status: int) -> int:
    if status >= 500:
        return logging.ERROR
    if status >= 400:
        return logging.WARNING
    return logging.INFO


class RequestLogMiddleware:
    """Log one line per HTTP request: method, path (no query string), status and latency."""

    def __init__(self, app: ASGIApp, project_id: str) -> None:
        self._app = app
        self._project_id = project_id

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self._app(scope, receive, send)
            return

        started = time.perf_counter()
        status = 500  # Stays 500 if the app raises before starting a response.

        async def send_with_status(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        trace = trace_resource(self._project_id, Headers(scope=scope).get("x-cloud-trace-context"))
        reset_token = _current_trace.set(trace)
        try:
            await self._app(scope, receive, send_with_status)
        finally:
            latency = time.perf_counter() - started
            method, path = scope["method"], scope["path"]
            _request_logger.log(
                _severity(status),
                "%s %s %d",
                method,
                path,
                status,
                extra={
                    "json_fields": {
                        "httpRequest": {
                            "requestMethod": method,
                            "requestUrl": path,
                            "status": status,
                            "latency": f"{latency:.6f}s",
                        }
                    }
                },
            )
            _current_trace.reset(reset_token)
