"""POST /v1/answers: submit an answer to a deterministically graded exercise
(choice, order, fill_blank, hallucination, story, live_check, agent). For agent the server
also runs the agent (ADK) to show the steps; the grading itself is still deterministic.

The server looks up the answer key, records the attempt, awards XP and returns the result
including the correct answer and explanation.
"""

from typing import Annotated, Literal, Self

from pydantic import Field, model_validator

from app.schemas.common import Contract, Id, ProgressSnapshot
from app.schemas.content import HallucinationError, Scene
from app.schemas.live_check import WebSource

# ---- Request ------------------------------------------------------------------------------


class ChoiceAnswer(Contract):
    type: Literal["choice"]
    option_id: Id


class OrderAnswer(Contract):
    type: Literal["order"]
    item_ids: list[Id] = Field(min_length=2, max_length=8)

    @model_validator(mode="after")
    def _unique(self) -> Self:
        if len(set(self.item_ids)) != len(self.item_ids):
            raise ValueError("item_ids must be unique")
        return self


class FillBlankAnswer(Contract):
    type: Literal["fill_blank"]
    selected_options: dict[Id, Id] = Field(min_length=1, max_length=4)


class HallucinationAnswer(Contract):
    """Indexes of the sentences the learner thinks are wrong. May be empty."""

    type: Literal["hallucination"]
    sentence_indexes: list[int] = Field(max_length=12)

    @model_validator(mode="after")
    def _valid_indexes(self) -> Self:
        if any(i < 0 for i in self.sentence_indexes):
            raise ValueError("sentence_indexes must be non-negative")
        if len(set(self.sentence_indexes)) != len(self.sentence_indexes):
            raise ValueError("sentence_indexes must be unique")
        return self


class StoryAnswer(Contract):
    type: Literal["story"]
    option_id: Id


class LiveCheckAnswer(Contract):
    """Indexes of the sentences of the session's answer that the learner thinks are wrong."""

    type: Literal["live_check"]
    session_id: Id
    sentence_indexes: list[int] = Field(max_length=12)

    @model_validator(mode="after")
    def _valid_indexes(self) -> Self:
        if any(i < 0 for i in self.sentence_indexes):
            raise ValueError("sentence_indexes must be non-negative")
        if len(set(self.sentence_indexes)) != len(self.sentence_indexes):
            raise ValueError("sentence_indexes must be unique")
        return self


class AgentAnswer(Contract):
    """The blocks the learner put into the agent. Order of tools does not matter."""

    type: Literal["agent"]
    tool_ids: list[Id] = Field(min_length=1, max_length=6)
    rule_ids: list[Id] = Field(max_length=4)

    @model_validator(mode="after")
    def _unique(self) -> Self:
        for ids in (self.tool_ids, self.rule_ids):
            if len(set(ids)) != len(ids):
                raise ValueError("block ids must be unique")
        return self


Answer = Annotated[
    ChoiceAnswer
    | OrderAnswer
    | FillBlankAnswer
    | HallucinationAnswer
    | StoryAnswer
    | LiveCheckAnswer
    | AgentAnswer,
    Field(discriminator="type"),
]


class SubmitAnswerRequest(Contract):
    exercise_id: Id
    answer: Answer


# ---- Response -----------------------------------------------------------------------------


class ChoiceResult(Contract):
    type: Literal["choice"]
    correct_option_id: Id
    explanation: str


class OrderResult(Contract):
    type: Literal["order"]
    correct_order: list[Id]
    explanation: str


class FillBlankResult(Contract):
    type: Literal["fill_blank"]
    correct_options: dict[Id, Id]
    explanation: str


class HallucinationResult(Contract):
    type: Literal["hallucination"]
    errors: list[HallucinationError]
    found: list[int] = Field(description="Wrong sentences the learner tapped")
    missed: list[int] = Field(description="Wrong sentences the learner did not tap")
    false_alarms: list[int] = Field(description="Correct sentences the learner tapped")


class StoryResult(Contract):
    type: Literal["story"]
    best_option_id: Id
    outcome: list[Scene] = Field(description="What happens after the learner's choice")
    explanation: str


class LiveCheckResult(Contract):
    type: Literal["live_check"]
    errors: list[HallucinationError] = Field(description="The rewritten sentences")
    found: list[int]
    missed: list[int]
    false_alarms: list[int]
    sources: list[WebSource] = Field(description="Google Search sources of the correct answer")


AgentStepKind = Literal["think", "tool", "observe", "ask_human", "answer", "give_up"]


class AgentStep(Contract):
    """One step of the agent run, shown in order. `tool_id` is set for tool and observe."""

    kind: AgentStepKind
    text: str
    tool_id: Id | None = None

    @model_validator(mode="after")
    def _tool_id_matches_kind(self) -> Self:
        if (self.kind in ("tool", "observe")) != (self.tool_id is not None):
            raise ValueError("tool_id is set exactly for tool and observe steps")
        return self


class AgentResult(Contract):
    type: Literal["agent"]
    steps: list[AgentStep] = Field(min_length=1, max_length=20)
    missing_tool_ids: list[Id]
    missing_rule_ids: list[Id]
    forbidden_tool_ids: list[Id] = Field(description="Forbidden tools the learner picked")
    explanation: str


AnswerResult = Annotated[
    ChoiceResult
    | OrderResult
    | FillBlankResult
    | HallucinationResult
    | StoryResult
    | LiveCheckResult
    | AgentResult,
    Field(discriminator="type"),
]


class SubmitAnswerResponse(Contract):
    attempt_id: Id
    correct: bool
    result: AnswerResult
    progress: ProgressSnapshot
