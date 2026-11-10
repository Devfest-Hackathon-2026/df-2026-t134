"""The only way the API talks to a generative model (Gemini on Vertex AI in production).

Services depend on the ``JsonGenerator`` protocol, so tests use a fake and the provider can
be swapped without touching them. Every output is parsed into a Pydantic model before it is
returned: callers never see raw model text.
"""

from dataclasses import dataclass
from typing import Protocol

from pydantic import BaseModel


class AiUnavailable(Exception):
    """The model could not produce a usable answer: not configured, timed out, failed, or
    returned output that does not match the schema. Callers answer 503 or fall back."""


class AiBlocked(Exception):
    """The provider's safety filter blocked the input or the output."""


@dataclass(frozen=True, slots=True)
class GenerationRequest:
    # Fixed instructions of the feature (role, rules, rubric). Never contains learner input.
    system_instruction: str
    # The user turn, which may contain learner input.
    contents: str
    temperature: float

    def __post_init__(self) -> None:
        if not self.system_instruction.strip() or not self.contents.strip():
            raise ValueError("system_instruction and contents must not be empty")
        if not 0.0 <= self.temperature <= 2.0:
            raise ValueError("temperature must be between 0 and 2")


class JsonGenerator(Protocol):
    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        """Generate JSON that matches schema and return it parsed.

        Raises AiBlocked when the safety filter stopped the request and AiUnavailable for
        every other failure.
        """
        ...


@dataclass(frozen=True, slots=True)
class Source:
    """A web page the model's answer is grounded on (for a human to check the facts)."""

    title: str
    uri: str


@dataclass(frozen=True, slots=True)
class GroundedSegment:
    """A part of the answer text (as the model wrote it) and the pages that support it."""

    text: str
    sources: tuple[Source, ...]


@dataclass(frozen=True, slots=True)
class GroundedText:
    text: str
    sources: tuple[Source, ...]
    # Which parts of the text which pages support (Google Search grounding supports).
    segments: tuple[GroundedSegment, ...] = ()


class GroundedWriter(Protocol):
    def write(self, request: GenerationRequest) -> GroundedText:
        """Plain text written with Google Search grounding, and the pages it is based on.

        The caller parses the text into a model. Raises AiUnavailable when the answer has no
        sources, so nothing ungrounded passes for checked facts, and AiBlocked as above.
        """
        ...


class SearchAnswerer(Protocol):
    def answer(self, request: GenerationRequest) -> GroundedText:
        """Plain text written with Google Search grounding, with its sources and segments.

        Unlike GroundedWriter.write, an answer without sources is returned as is (the model
        may decline to answer without searching); the caller decides what that means.
        Raises AiBlocked when the safety filter stopped the request and AiUnavailable for
        every other failure.
        """
        ...


class UnconfiguredGenerator:
    """Used when GEMINI_MODEL is not set (local development without Google Cloud)."""

    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        raise AiUnavailable("GEMINI_MODEL is not set, so AI features are turned off")


class UnconfiguredAnswerer:
    """SearchAnswerer used when GEMINI_MODEL is not set (local development)."""

    def answer(self, request: GenerationRequest) -> GroundedText:
        raise AiUnavailable("GEMINI_MODEL is not set, so AI features are turned off")
