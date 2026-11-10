"""Request-scoped access to what create_app was given (no module-level singletons)."""

from typing import Annotated

from fastapi import Depends, Request

from app.ai import JsonGenerator, SearchAnswerer
from app.clock import Clock
from app.config import Settings
from app.repo import LearningRepo
from app.services.feedback_audio import FeedbackSpeech


def get_repo(request: Request) -> LearningRepo:
    return request.app.state.repo


def get_clock(request: Request) -> Clock:
    return request.app.state.clock


def get_generator(request: Request) -> JsonGenerator:
    return request.app.state.generator


def get_speech(request: Request) -> FeedbackSpeech:
    return request.app.state.speech


def get_answerer(request: Request) -> SearchAnswerer:
    return request.app.state.answerer


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


RepoDep = Annotated[LearningRepo, Depends(get_repo)]
ClockDep = Annotated[Clock, Depends(get_clock)]
GeneratorDep = Annotated[JsonGenerator, Depends(get_generator)]
SpeechDep = Annotated[FeedbackSpeech, Depends(get_speech)]
AnswererDep = Annotated[SearchAnswerer, Depends(get_answerer)]
SettingsDep = Annotated[Settings, Depends(get_settings)]
