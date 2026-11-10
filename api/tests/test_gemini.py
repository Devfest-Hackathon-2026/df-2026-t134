"""The Gemini wrapper with a fake ``client.models`` (no network, no credentials)."""

import gc

import httpx2
import pytest
from google.genai import errors, types
from pydantic import Field

from app.ai import (
    AiBlocked,
    AiUnavailable,
    GenerationRequest,
    GroundedSegment,
    GroundedText,
    Source,
    UnconfiguredGenerator,
    gemini,
)
from app.ai.gemini import SAFETY_SETTINGS, GeminiGroundedWriter, GeminiJsonGenerator
from app.main import build_generator
from app.schemas.common import Contract
from tests.fakes import make_settings

REQUEST = GenerationRequest(system_instruction="rules", contents="learner text", temperature=0.2)


class Output(Contract):
    score: int = Field(ge=0, le=2)
    good_point: str


class FakeModels:
    """Returns one response (or raises one error) and records the call."""

    def __init__(self, result: types.GenerateContentResponse | Exception) -> None:
        self.result = result
        self.calls: list[dict[str, object]] = []

    def generate_content(
        self, *, model: str, contents: str, config: types.GenerateContentConfig
    ) -> types.GenerateContentResponse:
        self.calls.append({"model": model, "contents": contents, "config": config})
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def _response(
    text: str | None, finish: types.FinishReason | None = types.FinishReason.STOP
) -> types.GenerateContentResponse:
    parts = [] if text is None else [types.Part(text=text)]
    content = types.Content(role="model", parts=parts)
    return types.GenerateContentResponse(
        candidates=[types.Candidate(content=content, finish_reason=finish)]
    )


def _generate(result: types.GenerateContentResponse | Exception) -> Output:
    return GeminiJsonGenerator(FakeModels(result), "test-model").generate(REQUEST, Output)


def test_output_is_parsed_into_the_schema() -> None:
    assert _generate(_response('{"score": 2, "goodPoint": "よい"}')) == Output(
        score=2, good_point="よい"
    )


def test_request_carries_the_model_rules_schema_and_strict_safety() -> None:
    models = FakeModels(_response('{"score": 1, "goodPoint": "x"}'))

    GeminiJsonGenerator(models, "test-model").generate(REQUEST, Output)

    [call] = models.calls
    assert call["model"] == "test-model"
    assert call["contents"] == "learner text"
    config = call["config"]
    assert isinstance(config, types.GenerateContentConfig)
    assert config.system_instruction == "rules"
    assert config.temperature == 0.2
    assert config.response_mime_type == "application/json"
    assert config.response_schema is Output
    assert config.safety_settings == SAFETY_SETTINGS
    assert {setting.threshold for setting in SAFETY_SETTINGS} == {
        types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE
    }


@pytest.mark.parametrize(
    "text",
    [
        '{"score": 3, "goodPoint": "x"}',
        '{"score": 1}',
        "not json",
        '{"score": 1, "goodPoint": "x", "x": 1}',
    ],
    ids=["out of range", "missing field", "not json", "unknown field"],
)
def test_output_that_does_not_match_the_schema_is_unavailable(text: str) -> None:
    with pytest.raises(AiUnavailable, match="does not match the schema"):
        _generate(_response(text))


def test_blocked_input_is_reported_as_blocked() -> None:
    feedback = types.GenerateContentResponsePromptFeedback(block_reason=types.BlockedReason.SAFETY)

    with pytest.raises(AiBlocked, match="input blocked"):
        _generate(types.GenerateContentResponse(prompt_feedback=feedback))


@pytest.mark.parametrize(
    "finish",
    [
        types.FinishReason.SAFETY,
        types.FinishReason.BLOCKLIST,
        types.FinishReason.PROHIBITED_CONTENT,
        types.FinishReason.SPII,
    ],
)
def test_blocked_output_is_reported_as_blocked(finish: types.FinishReason) -> None:
    with pytest.raises(AiBlocked, match="output blocked"):
        _generate(_response(None, finish))


def test_output_cut_short_is_unavailable() -> None:
    with pytest.raises(AiUnavailable, match="stopped early"):
        _generate(_response('{"score": 1', types.FinishReason.MAX_TOKENS))


@pytest.mark.parametrize(
    "response",
    [types.GenerateContentResponse(candidates=[]), _response(None)],
    ids=["no candidates", "no text"],
)
def test_empty_response_is_unavailable(response: types.GenerateContentResponse) -> None:
    with pytest.raises(AiUnavailable):
        _generate(response)


@pytest.mark.parametrize(
    "error",
    [
        errors.ServerError(503, {"error": {"code": 503, "message": "x", "status": "UNAVAILABLE"}}),
        errors.ClientError(429, {"error": {"code": 429, "message": "x", "status": "QUOTA"}}),
        httpx2.ReadTimeout("timed out"),
        httpx2.ConnectError("refused"),
    ],
    ids=["server error", "quota", "timeout", "connection"],
)
def test_failed_call_is_unavailable(error: Exception) -> None:
    with pytest.raises(AiUnavailable, match="request failed"):
        _generate(error)


def test_bugs_in_the_call_are_not_hidden() -> None:
    with pytest.raises(TypeError):
        _generate(TypeError("unexpected keyword argument"))


def test_generator_is_turned_off_without_gemini_settings() -> None:
    generator = build_generator(make_settings())

    assert isinstance(generator, UnconfiguredGenerator)
    with pytest.raises(AiUnavailable, match="GEMINI_MODEL is not set"):
        generator.generate(REQUEST, Output)


@pytest.mark.parametrize(
    ("system_instruction", "contents", "temperature"),
    [(" ", "x", 0.2), ("x", "", 0.2), ("x", "x", -0.1), ("x", "x", 2.5)],
)
def test_invalid_generation_request_is_rejected(
    system_instruction: str, contents: str, temperature: float
) -> None:
    with pytest.raises(ValueError):
        GenerationRequest(system_instruction, contents, temperature)


def _grounded(text: str | None, *pages: tuple[str | None, str]) -> types.GenerateContentResponse:
    response = _response(text)
    chunks = [types.GroundingChunk(web=types.GroundingChunkWeb(title=t, uri=u)) for t, u in pages]
    response.candidates[0].grounding_metadata = types.GroundingMetadata(grounding_chunks=chunks)  # type: ignore[index]
    return response


def test_grounded_text_comes_with_its_sources() -> None:
    models = FakeModels(
        _grounded("光合成は葉で行われます。", ("mext.go.jp", "https://a"), (None, "https://b"))
    )

    result = GeminiGroundedWriter(models, "test-model").write(REQUEST)

    assert result == GroundedText(
        text="光合成は葉で行われます。",
        sources=(
            Source(title="mext.go.jp", uri="https://a"),
            Source(title="https://b", uri="https://b"),
        ),
    )
    [call] = models.calls
    config = call["config"]
    assert isinstance(config, types.GenerateContentConfig)
    assert config.tools == [types.Tool(google_search=types.GoogleSearch())]
    assert config.response_schema is None
    assert config.safety_settings == SAFETY_SETTINGS


def test_repeated_sources_are_listed_once() -> None:
    page = ("site", "https://a")

    result = GeminiGroundedWriter(FakeModels(_grounded("x", page, page)), "m").write(REQUEST)

    assert result.sources == (Source(title="site", uri="https://a"),)


def test_text_without_sources_is_unavailable() -> None:
    with pytest.raises(AiUnavailable, match="without search sources"):
        GeminiGroundedWriter(FakeModels(_response("根拠なし")), "m").write(REQUEST)


def test_grounded_writer_reports_blocks_and_failures_like_the_generator() -> None:
    blocked = _response(None, types.FinishReason.SAFETY)
    failure = httpx2.ReadTimeout("timed out")

    with pytest.raises(AiBlocked):
        GeminiGroundedWriter(FakeModels(blocked), "m").write(REQUEST)
    with pytest.raises(AiUnavailable, match="request failed"):
        GeminiGroundedWriter(FakeModels(failure), "m").write(REQUEST)


def _supported(
    text: str, pages: list[tuple[str, str]], supports: list[tuple[str, list[int]]]
) -> types.GenerateContentResponse:
    response = _grounded(text, *pages)
    metadata = response.candidates[0].grounding_metadata  # type: ignore[index]
    metadata.grounding_supports = [  # type: ignore[union-attr]
        types.GroundingSupport(segment=types.Segment(text=segment), grounding_chunk_indices=indexes)
        for segment, indexes in supports
    ]
    return response


def test_search_answer_keeps_which_pages_support_which_segment() -> None:
    response = _supported(
        "OK\n一文目。\n二文目。",
        [("a.jp", "https://a"), ("b.jp", "https://b"), ("a.jp", "https://a")],
        [("一文目。", [0, 2]), ("二文目。", [1, 9]), ("", [0])],
    )

    result = GeminiGroundedWriter(FakeModels(response), "m").answer(REQUEST)

    a, b = Source(title="a.jp", uri="https://a"), Source(title="b.jp", uri="https://b")
    assert result.sources == (a, b)
    assert result.segments == (
        GroundedSegment(text="一文目。", sources=(a,)),
        GroundedSegment(text="二文目。", sources=(b,)),
    )


def test_search_answer_without_sources_is_returned_for_the_caller_to_judge() -> None:
    result = GeminiGroundedWriter(FakeModels(_response("OFF_TOPIC")), "m").answer(REQUEST)

    assert result == GroundedText(text="OFF_TOPIC", sources=(), segments=())


def test_search_answer_reports_blocks_like_the_writer() -> None:
    with pytest.raises(AiBlocked):
        GeminiGroundedWriter(FakeModels(_response(None, types.FinishReason.SAFETY)), "m").answer(
            REQUEST
        )


class _ClosingClient:
    """Like genai.Client: its connection closes when it is garbage collected."""

    def __init__(self, **options: object) -> None:
        # Shared with models, which (like the SDK's) does not keep the client alive.
        self.connection = {"open": True}
        self.models = _ClientCalls(self.connection)

    def __del__(self) -> None:
        self.connection["open"] = False


class _ClientCalls:
    def __init__(self, connection: dict[str, bool]) -> None:
        self._connection = connection

    def generate_content(self, **call: object) -> types.GenerateContentResponse:
        assert self._connection["open"], "the client has been closed"
        return _response(OUTPUT_JSON)


OUTPUT_JSON = '{"score": 1, "goodPoint": "x"}'


def test_vertex_models_keep_their_client_open(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(gemini.genai, "Client", _ClosingClient)

    models = gemini.vertex_models("project", "global", 15)
    gc.collect()

    assert GeminiJsonGenerator(models, "m").generate(REQUEST, Output).score == 1
