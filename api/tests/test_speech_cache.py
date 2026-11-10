import pytest

from app.speech_cache import CachedSpeech, audio_path


def test_audio_path_is_a_hash_of_voice_and_text_under_the_folder() -> None:
    path = audio_path("audio/lines/", "voice-a", "こんにちは")

    assert path.startswith("audio/lines/") and path.endswith(".mp3")
    assert len(path.removeprefix("audio/lines/").removesuffix(".mp3")) == 64
    assert path == audio_path("audio/lines/", "voice-a", "こんにちは")
    assert path != audio_path("audio/lines/", "voice-b", "こんにちは")
    assert path != audio_path("audio/lines/", "voice-a", "こんばんは")


@pytest.mark.parametrize("prefix", ["private/", "audio", "audiofeedback/", ""])
def test_audio_outside_an_audio_folder_is_rejected(prefix: str) -> None:
    with pytest.raises(ValueError, match="under audio/"):
        audio_path(prefix, "voice", "text")


def test_cache_needs_a_voice() -> None:
    with pytest.raises(ValueError, match="at least one voice"):
        CachedSpeech(store=None, voices=[], prefix="audio/lines/")  # type: ignore[arg-type]
