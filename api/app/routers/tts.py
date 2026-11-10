from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.dependencies import RepoDep, SpeechDep
from app.errors import ERROR_RESPONSES
from app.schemas.tts import TtsRequest, TtsResponse
from app.services import feedback_audio

router = APIRouter(prefix="/v1", tags=["tts"], responses=ERROR_RESPONSES)


@router.post("/tts", response_model=TtsResponse)
def synthesize_feedback(
    body: TtsRequest, user: CurrentUserDep, repo: RepoDep, speech: SpeechDep
) -> TtsResponse:
    """Return the audio of the feedback for one of the caller's attempts."""
    return feedback_audio.speak_feedback(repo, speech, user.uid, body.attempt_id)
