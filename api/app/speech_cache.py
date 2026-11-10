"""Spoken audio cached in Cloud Storage under a hash of (voice, text) (requirements §5.4).

Used by POST /v1/tts for feedback and by the content tools for the mascot's fixed lines, so a
text is synthesized once per voice.
"""

import hashlib
import logging
from collections.abc import Sequence

from app.ai import AiUnavailable
from app.ai.speech import AUDIO_CONTENT_TYPE, SpeechSynthesizer
from app.storage import AudioStore

_logger = logging.getLogger("app.speech")


def _require_audio_folder(prefix: str) -> None:
    if not prefix.startswith("audio/") or not prefix.endswith("/"):
        raise ValueError("prefix must be a folder under audio/ (the only path clients read)")


def audio_path(prefix: str, voice_id: str, text: str) -> str:
    _require_audio_folder(prefix)
    digest = hashlib.sha256(f"{voice_id}\n{text}".encode()).hexdigest()
    return f"{prefix}{digest}.mp3"


class CachedSpeech:
    """Each voice in order of preference (the mascot's first, then the fallbacks): its stored
    audio of the text, else new audio from it, which is stored for the next time.

    A fallback is used only while the voices before it fail, so a short outage of the
    mascot's voice does not leave a text in the fallback voice for good.
    """

    def __init__(self, store: AudioStore, voices: Sequence[SpeechSynthesizer], prefix: str) -> None:
        if not voices:
            raise ValueError("at least one voice is needed")
        _require_audio_folder(prefix)
        self._store = store
        self._voices = tuple(voices)
        self._prefix = prefix

    def audio_path_for(self, text: str) -> str:
        """Storage path of the audio of text. Raises AiUnavailable when no voice can speak."""
        for voice in self._voices:
            path = audio_path(self._prefix, voice.voice_id, text)
            if self._store.exists(path):
                return path
            try:
                audio = voice.synthesize(text)
            except AiUnavailable as exc:
                _logger.warning(
                    "voice unavailable",
                    extra={"json_fields": {"voiceId": voice.voice_id, "reason": str(exc)}},
                )
                continue
            self._store.put(path, audio, AUDIO_CONTENT_TYPE)
            return path
        raise AiUnavailable("every voice failed")
