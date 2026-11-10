# Content tools (validate / seed). The repo is mounted at /repo by compose.yaml:
# /repo/tools (this project), /repo/content (read-only), /repo/api (read-only, for the contracts).
FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PYTHONUNBUFFERED=1

WORKDIR /repo/tools
COPY pyproject.toml uv.lock ./
RUN uv sync --locked

CMD ["python", "-m", "content_tools", "--help"]
