"""How each speaker of the story scenes sounds (Gemini-TTS voice and speaking style).

The mascot keeps the voice of the API (app.mascot), so its scene lines and intros share one
cache. Every other speaker gets its own Gemini-TTS voice; when it fails, the Chirp 3 HD
voice of the same name reads the line plainly (as for the mascot).
"""

from dataclasses import dataclass

from app.ai.speech import CloudTtsSynthesizer, TtsClient, chirp_voice, gemini_voice
from app.mascot import STYLE_PROMPT
from app.schemas.content import Speaker


@dataclass(frozen=True)
class Voice:
    name: str  # Gemini-TTS voice name (also the Chirp 3 HD fallback)
    style_prompt: str


SCENE_VOICES: dict[Speaker, Voice] = {
    "narrator": Voice(
        "Sulafat",
        "絵本の読み聞かせのように、落ち着いたあたたかい声で、ゆっくりやさしく読んでください。",
    ),
    "student": Voice(
        "Zephyr",
        "中学2年生の女の子として、明るく元気に、友だちと話すような自然な話し言葉で読んでください。",
    ),
    "friend": Voice(
        "Puck",
        "中学2年生の男の子として、元気で少しおちゃめに、自然な話し言葉で読んでください。",
    ),
    "teacher": Voice(
        "Kore",
        "中学校の先生として、生徒に語りかけるように、あたたかく落ち着いた声ではっきり読んでください。",
    ),
    "ai": Voice(
        "Iapetus",
        "親切なAIアシスタントとして、少し機械的で平らな調子で、でもやさしく丁寧に読んでください。",
    ),
}


def voices_for(
    client: TtsClient, model: str, speaker: Speaker, mascot_voice: str
) -> list[CloudTtsSynthesizer]:
    """The speaker's voice, then its fallback (in order of preference)."""
    voice = Voice(mascot_voice, STYLE_PROMPT) if speaker == "mascot" else SCENE_VOICES[speaker]
    return [
        gemini_voice(client, model, voice.name, voice.style_prompt),
        chirp_voice(client, voice.name),
    ]
