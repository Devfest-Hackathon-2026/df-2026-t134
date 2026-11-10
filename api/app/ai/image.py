"""Pictures from a Gemini image model on Vertex AI (story illustrations; content tools only).

The model ID comes from IMAGE_MODEL (read by the content tools); this module names no model.
Credentials are Application Default Credentials, as for the other Gemini calls.
"""

from dataclasses import dataclass
from typing import Protocol

from google.genai import errors, types

from app.ai import AiBlocked, AiUnavailable
from app.ai.gemini import _BLOCKED_FINISH_REASONS, _CALL_ERRORS, SAFETY_SETTINGS, ContentModels

# Wide enough for a picture-book panel, still readable on a phone in portrait.
ASPECT_RATIO = "3:2"
# JPEG keeps a scene around 100-300 KB, which matters on school networks.
OUTPUT_MIME_TYPE = "image/jpeg"
JPEG_QUALITY = 82


class ImageRateLimited(AiUnavailable):
    """The quota is used up for now (HTTP 429); nothing was generated or billed. Try again
    after a pause."""


@dataclass(frozen=True, slots=True)
class GeneratedImage:
    data: bytes
    mime_type: str


class ImageGenerator(Protocol):
    @property
    def model(self) -> str:
        """Everything that changes the picture besides the prompt (so images can be cached
        under (model, prompt))."""
        ...

    def generate(self, prompt: str) -> GeneratedImage:
        """One picture for prompt. Raises AiBlocked when the safety filter stopped it and
        AiUnavailable for every other failure."""
        ...


class GeminiImageGenerator:
    def __init__(self, models: ContentModels, model: str) -> None:
        if not model:
            raise ValueError("model must not be empty")
        self._models = models
        self._model = model

    @property
    def model(self) -> str:
        return self._model

    def generate(self, prompt: str) -> GeneratedImage:
        if not prompt.strip():
            raise ValueError("prompt must not be empty")
        config = types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(
                aspect_ratio=ASPECT_RATIO,
                output_mime_type=OUTPUT_MIME_TYPE,
                output_compression_quality=JPEG_QUALITY,
            ),
            safety_settings=SAFETY_SETTINGS,
        )
        try:
            response = self._models.generate_content(
                model=self._model, contents=prompt, config=config
            )
        except errors.ClientError as exc:
            if exc.code == 429:
                raise ImageRateLimited("the image model quota is used up for now") from exc
            raise AiUnavailable(f"image request failed (ClientError {exc.code})") from exc
        except _CALL_ERRORS as exc:
            raise AiUnavailable(f"image request failed ({type(exc).__name__})") from exc
        return parse_image_response(response)


def parse_image_response(response: types.GenerateContentResponse) -> GeneratedImage:
    """The first image of the first candidate, or AiBlocked / AiUnavailable."""
    feedback = response.prompt_feedback
    if feedback is not None and feedback.block_reason is not None:
        raise AiBlocked(f"input blocked ({feedback.block_reason})")
    if not response.candidates:
        raise AiUnavailable("the image model returned no candidates")
    candidate = response.candidates[0]
    if candidate.finish_reason in _BLOCKED_FINISH_REASONS:
        raise AiBlocked(f"output blocked ({candidate.finish_reason})")
    parts = (candidate.content.parts if candidate.content else None) or []
    for part in parts:
        blob = part.inline_data
        if blob is not None and blob.data and (blob.mime_type or "").startswith("image/"):
            return GeneratedImage(data=blob.data, mime_type=blob.mime_type or "")
    raise AiUnavailable(f"the image model returned no image ({candidate.finish_reason})")
