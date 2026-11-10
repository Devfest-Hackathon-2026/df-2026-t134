"""JsonGenerator backed by Gemini on Vertex AI (Google Gen AI SDK).

Cloud Run authenticates with its service account (Application Default Credentials), so no
API key exists anywhere. The model ID comes from GEMINI_MODEL; this module names no model.
"""

from typing import Protocol

import httpx2
from google import genai
from google.auth.exceptions import GoogleAuthError
from google.genai import errors, types
from pydantic import BaseModel, ValidationError

from app.ai import (
    AiBlocked,
    AiUnavailable,
    GenerationRequest,
    GroundedSegment,
    GroundedText,
    Source,
)

# For requests a learner waits for; after this the request fails and the app can fall back.
LEARNER_TIMEOUT_SECONDS = 15
# A grounded answer a learner waits for (it searches first, so it takes longer).
GROUNDED_LEARNER_TIMEOUT_SECONDS = 25

# Learners are minors, so block everything the filter rates as low risk or above.
SAFETY_SETTINGS = [
    types.SafetySetting(category=category, threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE)
    for category in (
        types.HarmCategory.HARM_CATEGORY_HARASSMENT,
        types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
        types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
        types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
    )
]

_BLOCKED_FINISH_REASONS = frozenset(
    {
        types.FinishReason.SAFETY,
        types.FinishReason.BLOCKLIST,
        types.FinishReason.PROHIBITED_CONTENT,
        types.FinishReason.SPII,
    }
)

# What the SDK raises when the call itself fails (HTTP error, timeout, connection, credentials).
_CALL_ERRORS = (errors.APIError, httpx2.HTTPError, GoogleAuthError)


class ContentModels(Protocol):
    """The part of ``genai.Client.models`` this module uses (a fake in tests)."""

    def generate_content(
        self, *, model: str, contents: str, config: types.GenerateContentConfig
    ) -> types.GenerateContentResponse: ...


def vertex_models(project: str, location: str, timeout_seconds: int) -> ContentModels:
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    client = genai.Client(
        vertexai=True,
        project=project,
        location=location,
        http_options=types.HttpOptions(timeout=timeout_seconds * 1000),
    )
    return _ClientModels(client)


class _ClientModels:
    """``client.models`` that keeps its client alive: ``genai.Client`` closes its HTTP client
    when it is garbage collected, so returning ``client.models`` alone makes every call fail
    with "the client has been closed"."""

    def __init__(self, client: genai.Client) -> None:
        self._client = client

    def generate_content(
        self, *, model: str, contents: str, config: types.GenerateContentConfig
    ) -> types.GenerateContentResponse:
        return self._client.models.generate_content(model=model, contents=contents, config=config)


class GeminiJsonGenerator:
    def __init__(self, models: ContentModels, model: str) -> None:
        if not model:
            raise ValueError("model must not be empty")
        self._models = models
        self._model = model

    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        config = types.GenerateContentConfig(
            system_instruction=request.system_instruction,
            temperature=request.temperature,
            response_mime_type="application/json",
            response_schema=schema,
            safety_settings=SAFETY_SETTINGS,
        )
        response = _call(self._models, self._model, request, config)
        return parse_response(response, schema)


class GeminiGroundedWriter:
    """GroundedWriter (content tools) and SearchAnswerer (live checks) with Grounding with
    Google Search."""

    def __init__(self, models: ContentModels, model: str) -> None:
        if not model:
            raise ValueError("model must not be empty")
        self._models = models
        self._model = model

    def write(self, request: GenerationRequest) -> GroundedText:
        return parse_grounded_response(self._search(request))

    def answer(self, request: GenerationRequest) -> GroundedText:
        return parse_search_answer(self._search(request))

    def _search(self, request: GenerationRequest) -> types.GenerateContentResponse:
        # Structured output and the search tool do not combine on every model, so this asks
        # for plain text and the caller validates it.
        config = types.GenerateContentConfig(
            system_instruction=request.system_instruction,
            temperature=request.temperature,
            tools=[types.Tool(google_search=types.GoogleSearch())],
            safety_settings=SAFETY_SETTINGS,
        )
        return _call(self._models, self._model, request, config)


def _call(
    models: ContentModels,
    model: str,
    request: GenerationRequest,
    config: types.GenerateContentConfig,
) -> types.GenerateContentResponse:
    try:
        return models.generate_content(model=model, contents=request.contents, config=config)
    except _CALL_ERRORS as exc:
        raise AiUnavailable(f"Gemini request failed ({type(exc).__name__})") from exc


def parse_response[T: BaseModel](response: types.GenerateContentResponse, schema: type[T]) -> T:
    """The first candidate parsed into schema, or AiBlocked / AiUnavailable."""
    text = _usable_text(response)
    try:
        return schema.model_validate_json(text)
    except ValidationError as exc:
        # The output itself is not logged: it may quote what the learner typed.
        raise AiUnavailable("Gemini output does not match the schema") from exc


def parse_grounded_response(response: types.GenerateContentResponse) -> GroundedText:
    """The first candidate's text and its web sources (at least one), or AiBlocked /
    AiUnavailable."""
    grounded = parse_search_answer(response)
    if not grounded.sources:
        raise AiUnavailable("Gemini answered without search sources")
    return grounded


def parse_search_answer(response: types.GenerateContentResponse) -> GroundedText:
    """The first candidate's text, its web sources (possibly none) and which segments of the
    text they support, or AiBlocked / AiUnavailable."""
    text = _usable_text(response)
    metadata = response.candidates[0].grounding_metadata  # type: ignore[index]
    chunks = (metadata.grounding_chunks if metadata else None) or []
    # Positional, so that grounding supports can refer to chunks by index.
    by_index = [
        Source(title=chunk.web.title or chunk.web.uri, uri=chunk.web.uri)
        if chunk.web is not None and chunk.web.uri
        else None
        for chunk in chunks
    ]
    supports = (metadata.grounding_supports if metadata else None) or []
    segments = tuple(
        GroundedSegment(
            text=support.segment.text,
            sources=tuple(
                dict.fromkeys(
                    source
                    for index in support.grounding_chunk_indices or []
                    if 0 <= index < len(by_index) and (source := by_index[index]) is not None
                )
            ),
        )
        for support in supports
        if support.segment is not None and support.segment.text
    )
    sources = tuple(dict.fromkeys(source for source in by_index if source is not None))
    return GroundedText(text=text, sources=sources, segments=segments)


def _usable_text(response: types.GenerateContentResponse) -> str:
    feedback = response.prompt_feedback
    if feedback is not None and feedback.block_reason is not None:
        raise AiBlocked(f"input blocked ({feedback.block_reason})")
    if not response.candidates:
        raise AiUnavailable("Gemini returned no candidates")
    finish = response.candidates[0].finish_reason
    if finish in _BLOCKED_FINISH_REASONS:
        raise AiBlocked(f"output blocked ({finish})")
    if finish not in (types.FinishReason.STOP, None):
        raise AiUnavailable(f"Gemini stopped early ({finish})")
    text = response.text
    if not text:
        raise AiUnavailable("Gemini returned no text")
    return text
