"""Uniform error responses: every non-2xx body is an ErrorResponse."""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.schemas.common import ErrorBody, ErrorCode, ErrorResponse


class ApiError(Exception):
    """Raise from routers/services for expected failures that map to an HTTP status."""

    def __init__(self, status_code: int, code: ErrorCode, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def not_implemented(planned_in: str) -> ApiError:
    return ApiError(501, "not_implemented", f"Not implemented yet (planned in {planned_in})")


_STATUS_TO_CODE: dict[int, ErrorCode] = {
    400: "bad_request",
    401: "unauthenticated",
    403: "forbidden",
    404: "not_found",
    405: "bad_request",
    409: "conflict",
    429: "rate_limited",
    501: "not_implemented",
    503: "upstream_unavailable",
}

# Documented on every endpoint so that the generated OpenAPI lists the error body.
ERROR_RESPONSES: dict[int | str, dict[str, object]] = {
    status: {"model": ErrorResponse} for status in (400, 401, 403, 404, 429, 501, 503)
}


def _error_response(status_code: int, code: ErrorCode, message: str) -> JSONResponse:
    body = ErrorResponse(error=ErrorBody(code=code, message=message))
    return JSONResponse(status_code=status_code, content=body.model_dump(mode="json"))


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _error_response(exc.status_code, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        first = exc.errors()[0] if exc.errors() else {}
        location = ".".join(str(part) for part in first.get("loc", ()))
        message = f"{location}: {first.get('msg', 'invalid request')}" if location else "invalid"
        return _error_response(400, "bad_request", message)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _STATUS_TO_CODE.get(exc.status_code, "internal")
        return _error_response(exc.status_code, code, str(exc.detail))

    # Bugs keep the uniform body without exposing details; the server still logs the traceback.
    @app.exception_handler(Exception)
    async def _unexpected_error(_: Request, __: Exception) -> JSONResponse:
        return _error_response(500, "internal", "Internal server error")


def drop_default_validation_docs(app: FastAPI) -> None:
    """Validation errors are returned as 400 ErrorResponse, so remove FastAPI's default 422 docs."""
    generate = app.openapi

    def openapi() -> dict[str, object]:
        if app.openapi_schema:
            return app.openapi_schema
        schema = generate()
        for operations in schema.get("paths", {}).values():
            for operation in operations.values():
                operation.get("responses", {}).pop("422", None)
        for name in ("HTTPValidationError", "ValidationError"):
            schema.get("components", {}).get("schemas", {}).pop(name, None)
        return schema

    app.openapi = openapi  # type: ignore[method-assign]
