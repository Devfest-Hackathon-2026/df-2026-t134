"""Use case behind POST /v1/tts: the spoken feedback of one of the learner's attempts.

Only server-written feedback (Attempt.feedback_text) is spoken, so the endpoint is no general
text-to-speech proxy. Audio is cached (app.speech_cache): an explanation shared by every
learner is synthesized once.
"""

import logging
from typing import Protocol

from app.ai import AiUnavailable
from app.errors import ApiError
from app.repo import LearningRepo
from app.schemas.tts import TtsResponse

_logger = logging.getLogger("app.tts")

FEEDBACK_AUDIO_PREFIX = "audio/feedback/"


class FeedbackSpeech(Protocol):
    def audio_path_for(self, text: str) -> str:
        """Storage path of the audio of text. Raises AiUnavailable when nothing can speak."""
        ...


class UnconfiguredSpeech:
    """Used when TTS_MODEL is not set (local development without Google Cloud)."""

    def audio_path_for(self, text: str) -> str:
        raise AiUnavailable("TTS_MODEL is not set, so speech is turned off")


def speak_feedback(
    repo: LearningRepo, speech: FeedbackSpeech, uid: str, attempt_id: str
) -> TtsResponse:
    attempt = repo.get_attempt(uid, attempt_id)
    if attempt is None:
        raise ApiError(404, "not_found", "Attempt not found")
    try:
        path = speech.audio_path_for(attempt.feedback_text)
    except AiUnavailable as exc:
        _logger.warning(
            "feedback speech unavailable",
            extra={"json_fields": {"attemptId": attempt_id, "reason": str(exc)}},
        )
        raise ApiError(503, "upstream_unavailable", "Speech is not available right now") from exc
    return TtsResponse(storage_path=path)
