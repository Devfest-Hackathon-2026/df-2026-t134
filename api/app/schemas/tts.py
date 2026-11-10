"""POST /v1/tts: get the spoken audio of the feedback for one of the learner's attempts.

Only server-generated feedback can be spoken, so the endpoint cannot be used as a
general text-to-speech proxy.
"""

from app.schemas.common import Contract, Id


class TtsRequest(Contract):
    attempt_id: Id


class TtsResponse(Contract):
    storage_path: str  # Path in Cloud Storage, readable by signed-in users (audio/...)
