"""The image model wrapper with a fake ``client.models`` (no network, no credentials)."""

from typing import Any

import httpx2
import pytest
from google.genai import errors, types

from app.ai import AiBlocked, AiUnavailable
from app.ai.gemini import SAFETY_SETTINGS
from app.ai.image import (
    ASPECT_RATIO,
    OUTPUT_MIME_TYPE,
    GeminiImageGenerator,
    GeneratedImage,
    ImageRateLimited,
)
from app.storage import BucketImageStore


class FakeModels:
    def __init__(self, result: types.GenerateContentResponse | Exception) -> None:
        self.result = result
        self.calls: list[dict[str, Any]] = []

    def generate_content(
        self, *, model: str, contents: str, config: types.GenerateContentConfig
    ) -> types.GenerateContentResponse:
        self.calls.append({"model": model, "contents": contents, "config": config})
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


def _response(
    parts: list[types.Part], finish: types.FinishReason | None = types.FinishReason.STOP
) -> types.GenerateContentResponse:
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(content=types.Content(role="model", parts=parts), finish_reason=finish)
        ]
    )


def _image_part(data: bytes = b"jpeg-bytes", mime: str = "image/jpeg") -> types.Part:
    return types.Part(inline_data=types.Blob(data=data, mime_type=mime))


def test_returns_the_first_image_and_asks_for_one_picture_only() -> None:
    models = FakeModels(_response([types.Part(text="ここに絵"), _image_part()]))

    image = GeminiImageGenerator(models, "image-model").generate("a calm classroom")

    assert image == GeneratedImage(data=b"jpeg-bytes", mime_type="image/jpeg")
    [call] = models.calls
    assert call["model"] == "image-model"
    assert call["contents"] == "a calm classroom"
    config = call["config"]
    assert config.response_modalities == ["IMAGE"]
    assert config.image_config.aspect_ratio == ASPECT_RATIO
    assert config.image_config.output_mime_type == OUTPUT_MIME_TYPE
    assert config.safety_settings == SAFETY_SETTINGS


def test_no_image_is_unavailable() -> None:
    models = FakeModels(_response([types.Part(text="ごめんなさい")]))

    with pytest.raises(AiUnavailable, match="no image"):
        GeminiImageGenerator(models, "image-model").generate("a calm classroom")


def test_safety_block_is_blocked() -> None:
    models = FakeModels(_response([], finish=types.FinishReason.SAFETY))

    with pytest.raises(AiBlocked):
        GeminiImageGenerator(models, "image-model").generate("a calm classroom")


def test_call_failure_is_unavailable() -> None:
    models = FakeModels(httpx2.ConnectError("offline"))

    with pytest.raises(AiUnavailable, match="ConnectError"):
        GeminiImageGenerator(models, "image-model").generate("a calm classroom")


def test_quota_error_is_rate_limited_and_other_client_errors_are_unavailable() -> None:
    quota = errors.ClientError(429, {"error": {"code": 429, "status": "RESOURCE_EXHAUSTED"}})
    bad = errors.ClientError(400, {"error": {"code": 400, "status": "INVALID_ARGUMENT"}})

    with pytest.raises(ImageRateLimited):
        GeminiImageGenerator(FakeModels(quota), "image-model").generate("a calm classroom")
    with pytest.raises(AiUnavailable, match="ClientError 400") as raised:
        GeminiImageGenerator(FakeModels(bad), "image-model").generate("a calm classroom")
    assert not isinstance(raised.value, ImageRateLimited)


def test_model_and_prompt_must_not_be_empty() -> None:
    with pytest.raises(ValueError):
        GeminiImageGenerator(FakeModels(_response([])), "")
    with pytest.raises(ValueError):
        GeminiImageGenerator(FakeModels(_response([])), "image-model").generate(" ")


class FakeBlob:
    def __init__(self) -> None:
        self.cache_control: str | None = None
        self.uploads: list[tuple[bytes, str]] = []

    def upload_from_string(self, data: bytes, content_type: str) -> None:
        self.uploads.append((data, content_type))


class FakeBucket:
    def __init__(self) -> None:
        self.blobs: dict[str, FakeBlob] = {}

    def blob(self, path: str) -> FakeBlob:
        return self.blobs.setdefault(path, FakeBlob())


def test_image_store_writes_only_images_under_images() -> None:
    bucket = FakeBucket()
    store = BucketImageStore(bucket)  # type: ignore[arg-type]

    store.put("images/scenes/x.jpg", b"jpeg", "image/jpeg")

    blob = bucket.blobs["images/scenes/x.jpg"]
    assert blob.uploads == [(b"jpeg", "image/jpeg")]
    assert blob.cache_control is not None and "immutable" in blob.cache_control
    with pytest.raises(ValueError):
        store.put("audio/lines/x.jpg", b"jpeg", "image/jpeg")
    with pytest.raises(ValueError):
        store.put("images/scenes/x.mp3", b"mp3", "audio/mpeg")


def test_vertex_models_keep_their_client_open_after_garbage_collection() -> None:
    import gc

    from app.ai.gemini import vertex_models

    models = vertex_models("test-project", "global", 5)
    gc.collect()

    assert not models._client._api_client._httpx_client.is_closed  # type: ignore[attr-defined]
