"""The Cloud Text-to-Speech wrapper with a fake client (no network, no credentials)."""

import pytest
from google.api_core import exceptions as api_exceptions
from google.auth.exceptions import DefaultCredentialsError
from google.cloud import texttospeech

from app.ai import AiUnavailable
from app.ai.speech import (
    MAX_TEXT_BYTES,
    TIMEOUT_SECONDS,
    chirp_voice,
    gemini_voice,
    mascot_voices,
)
from app.mascot import STYLE_PROMPT

STYLE = "明るく読んでください。"


class FakeTtsClient:
    """Returns one response (or raises one error) and records each call."""

    def __init__(self, result: bytes | Exception = b"mp3-bytes") -> None:
        self.result = result
        self.calls: list[dict[str, object]] = []

    def synthesize_speech(
        self,
        *,
        input: texttospeech.SynthesisInput,
        voice: texttospeech.VoiceSelectionParams,
        audio_config: texttospeech.AudioConfig,
        timeout: float,
    ) -> texttospeech.SynthesizeSpeechResponse:
        self.calls.append(
            {"input": input, "voice": voice, "audio_config": audio_config, "timeout": timeout}
        )
        if isinstance(self.result, Exception):
            raise self.result
        return texttospeech.SynthesizeSpeechResponse(audio_content=self.result)


def test_mascot_voice_is_gemini_tts_with_the_style_prompt() -> None:
    client = FakeTtsClient()

    audio = gemini_voice(client, "test-tts-model", "Leda", STYLE).synthesize("正解です。")

    assert audio == b"mp3-bytes"
    [call] = client.calls
    assert call["input"] == texttospeech.SynthesisInput(text="正解です。", prompt=STYLE)
    assert call["voice"] == texttospeech.VoiceSelectionParams(
        language_code="ja-JP", name="Leda", model_name="test-tts-model"
    )
    assert call["audio_config"] == texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3
    )
    assert call["timeout"] == TIMEOUT_SECONDS


def test_fallback_voice_is_chirp_3_hd_without_a_model_or_prompt() -> None:
    client = FakeTtsClient()

    chirp_voice(client, "Leda").synthesize("正解です。")

    [call] = client.calls
    assert call["input"] == texttospeech.SynthesisInput(text="正解です。")
    assert call["voice"] == texttospeech.VoiceSelectionParams(
        language_code="ja-JP", name="ja-JP-Chirp3-HD-Leda"
    )


def test_voice_id_changes_with_everything_that_changes_the_sound() -> None:
    client = FakeTtsClient()
    base = gemini_voice(client, "m1", "Leda", STYLE).voice_id

    assert gemini_voice(client, "m1", "Leda", STYLE).voice_id == base
    others = {
        gemini_voice(client, "m2", "Leda", STYLE).voice_id,
        gemini_voice(client, "m1", "Puck", STYLE).voice_id,
        gemini_voice(client, "m1", "Leda", "ゆっくり読んでください。").voice_id,
        chirp_voice(client, "Leda").voice_id,
    }
    assert base not in others
    assert len(others) == 4


@pytest.mark.parametrize(
    "error",
    [
        api_exceptions.ServiceUnavailable("down"),
        api_exceptions.ResourceExhausted("quota"),
        api_exceptions.DeadlineExceeded("slow"),
        api_exceptions.InvalidArgument("model not found"),
        api_exceptions.RetryError("gave up", cause=None),
        DefaultCredentialsError("no credentials"),
    ],
    ids=["unavailable", "quota", "timeout", "bad request", "retries", "credentials"],
)
def test_failed_call_is_unavailable(error: Exception) -> None:
    with pytest.raises(AiUnavailable, match="failed"):
        chirp_voice(FakeTtsClient(error), "Leda").synthesize("こんにちは")


def test_empty_audio_is_unavailable() -> None:
    with pytest.raises(AiUnavailable, match="no audio"):
        chirp_voice(FakeTtsClient(b""), "Leda").synthesize("こんにちは")


def test_bugs_in_the_call_are_not_hidden() -> None:
    with pytest.raises(TypeError):
        chirp_voice(FakeTtsClient(TypeError("bad argument")), "Leda").synthesize("こんにちは")


@pytest.mark.parametrize("text", ["", "  ", "あ" * (MAX_TEXT_BYTES // 3 + 1)])
def test_empty_or_too_long_text_is_rejected_before_the_call(text: str) -> None:
    client = FakeTtsClient()

    with pytest.raises(ValueError):
        chirp_voice(client, "Leda").synthesize(text)
    assert client.calls == []


@pytest.mark.parametrize(
    ("model", "voice", "style"), [("", "Leda", STYLE), ("m", "", STYLE), ("m", "Leda", " ")]
)
def test_mascot_voice_needs_a_model_voice_and_style(model: str, voice: str, style: str) -> None:
    with pytest.raises(ValueError):
        gemini_voice(FakeTtsClient(), model, voice, style)


def test_mascot_speaks_in_its_style_first_then_falls_back_to_chirp() -> None:
    client = FakeTtsClient()

    mascot, fallback = mascot_voices(client, "test-tts-model", "Leda")

    assert mascot.voice_id == gemini_voice(client, "test-tts-model", "Leda", STYLE_PROMPT).voice_id
    assert fallback.voice_id == chirp_voice(client, "Leda").voice_id
