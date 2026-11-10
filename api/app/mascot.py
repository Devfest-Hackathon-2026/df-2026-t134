"""How the mascot sounds (requirements §4.5 and §5.4), shared by the API and the content tools."""

# Gemini-TTS voice name; the fallback is the Chirp 3 HD voice with the same name.
DEFAULT_VOICE = "Leda"

# Gemini-TTS takes the speaking style in natural language.
STYLE_PROMPT = "中学生に話しかけるように、明るくやさしい声で、ゆっくりはっきり読んでください。"
