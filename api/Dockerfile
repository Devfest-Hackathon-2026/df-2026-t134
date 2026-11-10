FROM python:3.13-slim AS base

COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PYTHONUNBUFFERED=1

WORKDIR /srv
COPY pyproject.toml uv.lock ./

# Local development: dev dependencies, source is bind-mounted, auto reload.
FROM base AS dev
RUN uv sync --locked
CMD ["uvicorn", "app.main:build_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# Cloud Run: runtime dependencies only, non-root user.
FROM base AS prod
RUN uv sync --locked --no-dev
COPY app ./app
RUN useradd --system --uid 10001 appuser
USER appuser
ENV PORT=8080
CMD ["sh", "-c", "exec uvicorn app.main:build_app --factory --host 0.0.0.0 --port ${PORT}"]
