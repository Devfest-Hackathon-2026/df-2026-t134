"""Text-to-speech through the Cloud Text-to-Speech API (requirements §5.4).

Two voices share this one client: the mascot's Gemini-TTS voice (a model named by TTS_MODEL,
steered by a style prompt) and, as the fallback, the Chirp 3 HD voice of the same name, which
needs no Gemini model (requirements §14 R6). Both return MP3.
"""

import hashlib
from typing import Protocol

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError
from google.cloud import texttospeech

from app.ai import AiUnavailable
from app.mascot import STYLE_PROMPT

LANGUAGE_CODE = "ja-JP"
AUDIO_CONTENT_TYPE = "audio/mpeg"
# Feedback is read right after an answer; past this the app keeps showing the subtitles only.
TIMEOUT_SECONDS = 15
# The API takes at most 4000 bytes of text per request (Gemini-TTS); feedback is far shorter.
MAX_TEXT_BYTES = 4000


class SpeechSynthesizer(Protocol):
    # Everything that changes the sound (engine, model, voice, style), so audio can be cached
    # under (voice_id, text).
    @property
    def voice_id(self) -> str: ...

    def synthesize(self, text: str) -> bytes:
        """MP3 of text. Raises AiUnavailable when the voice cannot speak right now."""
        ...


class TtsClient(Protocol):
    """The part of ``texttospeech.TextToSpeechClient`` this module uses (a fake in tests)."""

    def synthesize_speech(
        self,
        *,
        input: texttospeech.SynthesisInput,
        voice: texttospeech.VoiceSelectionParams,
        audio_config: texttospeech.AudioConfig,
        timeout: float,
    ) -> texttospeech.SynthesizeSpeechResponse: ...


def tts_client() -> TtsClient:
    return texttospeech.TextToSpeechClient()


class CloudTtsSynthesizer:
    def __init__(
        self,
        client: TtsClient,
        voice: texttospeech.VoiceSelectionParams,
        style_prompt: str | None,
        voice_id: str,
    ) -> None:
        self._client = client
        self._voice = voice
        self._style_prompt = style_prompt
        self._voice_id = voice_id

    @property
    def voice_id(self) -> str:
        return self._voice_id

    def synthesize(self, text: str) -> bytes:
        if not text.strip():
            raise ValueError("text must not be empty")
        if len(text.encode()) > MAX_TEXT_BYTES:
            raise ValueError(f"text must be at most {MAX_TEXT_BYTES} bytes")
        if self._style_prompt is None:
            synthesis_input = texttospeech.SynthesisInput(text=text)
        else:
            synthesis_input = texttospeech.SynthesisInput(text=text, prompt=self._style_prompt)
        try:
            response = self._client.synthesize_speech(
                input=synthesis_input,
                voice=self._voice,
                audio_config=texttospeech.AudioConfig(
                    audio_encoding=texttospeech.AudioEncoding.MP3
                ),
                timeout=TIMEOUT_SECONDS,
            )
        except (GoogleAPIError, GoogleAuthError) as exc:
            raise AiUnavailable(f"{self._voice_id} failed ({type(exc).__name__})") from exc
        if not response.audio_content:
            raise AiUnavailable(f"{self._voice_id} returned no audio")
        return response.audio_content


def gemini_voice(
    client: TtsClient, model: str, voice_name: str, style_prompt: str
) -> CloudTtsSynthesizer:
    """The mascot's voice: Gemini-TTS, read in the given style."""
    if not model or not voice_name or not style_prompt.strip():
        raise ValueError("model, voice_name and style_prompt must not be empty")
    style = hashlib.sha256(style_prompt.encode()).hexdigest()[:12]
    return CloudTtsSynthesizer(
        client,
        texttospeech.VoiceSelectionParams(
            language_code=LANGUAGE_CODE, name=voice_name, model_name=model
        ),
        style_prompt,
        voice_id=f"gemini-tts/{model}/{voice_name}/{style}",
    )


def chirp_voice(client: TtsClient, voice_name: str) -> CloudTtsSynthesizer:
    """The fallback: the Chirp 3 HD voice with the same name, without a style prompt."""
    if not voice_name:
        raise ValueError("voice_name must not be empty")
    name = f"{LANGUAGE_CODE}-Chirp3-HD-{voice_name}"
    return CloudTtsSynthesizer(
        client,
        texttospeech.VoiceSelectionParams(language_code=LANGUAGE_CODE, name=name),
        None,
        voice_id=f"chirp3-hd/{name}",
    )


def mascot_voices(client: TtsClient, model: str, voice_name: str) -> list[CloudTtsSynthesizer]:
    """The mascot's voice in its speaking style, then its fallback (in order of preference)."""
    return [gemini_voice(client, model, voice_name, STYLE_PROMPT), chirp_voice(client, voice_name)]
