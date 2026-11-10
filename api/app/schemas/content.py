"""Teaching material. Authored as YAML under content/ and loaded into Firestore by tools/.

Public parts (Unit, Lesson, Exercise) are readable by signed-in users.
AnswerKey is stored separately and is never readable by clients.
"""

from typing import Annotated, Literal, Self

from pydantic import Field, model_validator

from app.schemas.common import Contract, Id, NonEmptyText

Level = Literal[1, 2, 3, 4]


class Speech(Contract):
    """A line spoken by the mascot. audio_path is filled in when audio is pre-generated."""

    text: NonEmptyText
    audio_path: str | None = None


class Unit(Contract):
    id: Id
    order: int = Field(ge=1)
    title: NonEmptyText
    description: NonEmptyText
    level: Level


class Lesson(Contract):
    id: Id
    unit_id: Id
    order: int = Field(ge=1)
    title: NonEmptyText
    exercise_ids: list[Id] = Field(min_length=1, max_length=12)
    intro: Speech | None = None

    @model_validator(mode="after")
    def _unique_exercises(self) -> Self:
        if len(set(self.exercise_ids)) != len(self.exercise_ids):
            raise ValueError("exercise_ids must be unique")
        return self


class Option(Contract):
    id: Id
    text: NonEmptyText


def _require_unique_ids(items: list[Option], field: str) -> None:
    ids = [item.id for item in items]
    if len(set(ids)) != len(ids):
        raise ValueError(f"{field} ids must be unique")


# ---- Exercise bodies (public) -------------------------------------------------------------


class _ExerciseBase(Contract):
    id: Id
    lesson_id: Id
    question: NonEmptyText
    intro: Speech | None = None


class ChoiceExercise(_ExerciseBase):
    """Q1: pick one option (true/false is a two-option choice)."""

    type: Literal["choice"]
    options: list[Option] = Field(min_length=2, max_length=6)

    @model_validator(mode="after")
    def _unique(self) -> Self:
        _require_unique_ids(self.options, "options")
        return self


class OrderExercise(_ExerciseBase):
    """Q3: put the items in the right order. The app shuffles them before display."""

    type: Literal["order"]
    items: list[Option] = Field(min_length=2, max_length=8)

    @model_validator(mode="after")
    def _unique(self) -> Self:
        _require_unique_ids(self.items, "items")
        return self


class Blank(Contract):
    id: Id
    options: list[Option] = Field(min_length=2, max_length=6)


class FillBlankExercise(_ExerciseBase):
    """Q3: choose an option for every blank. The template marks blanks as {{blank_id}}."""

    type: Literal["fill_blank"]
    template: NonEmptyText
    blanks: list[Blank] = Field(min_length=1, max_length=4)

    @model_validator(mode="after")
    def _blanks_match_template(self) -> Self:
        ids = [blank.id for blank in self.blanks]
        if len(set(ids)) != len(ids):
            raise ValueError("blank ids must be unique")
        for blank in self.blanks:
            _require_unique_ids(blank.options, f"blank {blank.id} options")
            if self.template.count("{{" + blank.id + "}}") != 1:
                raise ValueError(f"template must contain {{{{{blank.id}}}}} exactly once")
        return self


class Sentence(Contract):
    index: int = Field(ge=0)
    text: NonEmptyText


class HallucinationExercise(_ExerciseBase):
    """Q2: an AI answer split into sentences; the learner taps the wrong ones."""

    type: Literal["hallucination"]
    topic: NonEmptyText
    sentences: list[Sentence] = Field(min_length=2, max_length=12)
    error_count: int = Field(ge=1, le=3)

    @model_validator(mode="after")
    def _indexes_are_sequential(self) -> Self:
        if [s.index for s in self.sentences] != list(range(len(self.sentences))):
            raise ValueError("sentence indexes must be 0..n-1 in order")
        if self.error_count >= len(self.sentences):
            raise ValueError("error_count must be smaller than the number of sentences")
        return self


Speaker = Literal["narrator", "mascot", "student", "friend", "teacher", "ai"]


class Illustration(Contract):
    """A picture for a story scene. `prompt` describes it for the image model (authoring);
    `image_path` (Cloud Storage) is filled in by the content tools, never written by hand."""

    prompt: NonEmptyText
    image_path: str | None = None


class Scene(Contract):
    """One panel of a story: who speaks, what they say, and optionally a picture.
    `audio_path` is filled in by the content tools (each speaker has its own voice)."""

    speaker: Speaker
    text: NonEmptyText
    audio_path: str | None = None
    illustration: Illustration | None = None


class StoryExercise(_ExerciseBase):
    """A short picture-story (kamishibai). The scenes play first, then `question` asks what
    the student should do, and the learner picks one of `options`. What happens next depends
    on the choice and is in the answer key."""

    type: Literal["story"]
    title: NonEmptyText
    scenes: list[Scene] = Field(min_length=1, max_length=8)
    options: list[Option] = Field(min_length=2, max_length=4)

    @model_validator(mode="after")
    def _unique(self) -> Self:
        _require_unique_ids(self.options, "options")
        return self


class LiveCheckExercise(_ExerciseBase):
    """The learner asks Gemini about `theme` with their own prompt. The server answers with
    sources from Google Search, secretly rewrites `error_count` sentences to be wrong, and the
    learner finds them, looking up sources at most `lookup_limit` times."""

    type: Literal["live_check"]
    theme: NonEmptyText
    suggestions: list[NonEmptyText] = Field(min_length=1, max_length=4)
    error_count: int = Field(ge=1, le=2)
    lookup_limit: int = Field(default=2, ge=0, le=5)
    max_length: int = Field(default=200, ge=20, le=400)


class AgentBlock(Contract):
    """A block the learner can put into the agent: a (mock) tool or a rule."""

    id: Id
    name: NonEmptyText
    description: NonEmptyText


class AgentExercise(_ExerciseBase):
    """Build an AI agent from blocks (F-12). The goal is given; the learner picks the tools and
    rules the agent gets. The server runs the agent (ADK, mock tools only) and shows each step:
    think -> use a tool -> look at the result, until it answers, asks a person or gives up."""

    type: Literal["agent"]
    goal: NonEmptyText
    situation: NonEmptyText
    tools: list[AgentBlock] = Field(min_length=2, max_length=6)
    rules: list[AgentBlock] = Field(min_length=1, max_length=4)
    # How many tools the agent may carry, so that picking everything is not a strategy.
    max_tools: int = Field(ge=1, le=6)

    @model_validator(mode="after")
    def _unique_blocks(self) -> Self:
        ids = [block.id for block in [*self.tools, *self.rules]]
        if len(set(ids)) != len(ids):
            raise ValueError("tool and rule ids must be unique within the exercise")
        if self.max_tools > len(self.tools):
            raise ValueError("max_tools cannot exceed the number of tools")
        return self


class PromptExercise(_ExerciseBase):
    """Q4: write a prompt for the task; graded by Gemini with the shared rubric."""

    type: Literal["prompt"]
    task: NonEmptyText
    max_length: int = Field(default=400, ge=20, le=1000)


Exercise = Annotated[
    ChoiceExercise
    | OrderExercise
    | FillBlankExercise
    | HallucinationExercise
    | PromptExercise
    | StoryExercise
    | LiveCheckExercise
    | AgentExercise,
    Field(discriminator="type"),
]


# ---- Answer keys (server only) ------------------------------------------------------------


class ChoiceAnswerKey(Contract):
    type: Literal["choice"]
    correct_option_id: Id
    explanation: NonEmptyText


class OrderAnswerKey(Contract):
    type: Literal["order"]
    correct_order: list[Id] = Field(min_length=2, max_length=8)
    explanation: NonEmptyText


class FillBlankAnswerKey(Contract):
    type: Literal["fill_blank"]
    correct_options: dict[Id, Id] = Field(min_length=1, max_length=4)
    explanation: NonEmptyText


HallucinationErrorType = Literal["number", "date", "name", "fake_source", "causality", "fact"]


class HallucinationError(Contract):
    index: int = Field(ge=0)
    error_type: HallucinationErrorType
    correction: NonEmptyText
    tip: NonEmptyText


class HallucinationAnswerKey(Contract):
    type: Literal["hallucination"]
    errors: list[HallucinationError] = Field(min_length=1, max_length=3)

    @model_validator(mode="after")
    def _unique_indexes(self) -> Self:
        indexes = [e.index for e in self.errors]
        if len(set(indexes)) != len(indexes):
            raise ValueError("error indexes must be unique")
        return self


class PromptAnswerKey(Contract):
    """Notes for the grader about what a good prompt for this task contains."""

    type: Literal["prompt"]
    grading_notes: NonEmptyText


class StoryOutcome(Contract):
    """What happens after the learner picks `option_id`."""

    option_id: Id
    scenes: list[Scene] = Field(min_length=1, max_length=4)


class StoryAnswerKey(Contract):
    type: Literal["story"]
    best_option_id: Id
    outcomes: list[StoryOutcome] = Field(min_length=2, max_length=4)
    explanation: NonEmptyText

    @model_validator(mode="after")
    def _one_outcome_per_option(self) -> Self:
        ids = [outcome.option_id for outcome in self.outcomes]
        if len(set(ids)) != len(ids):
            raise ValueError("outcomes must have unique option ids")
        if self.best_option_id not in ids:
            raise ValueError("best_option_id must have an outcome")
        return self


class LiveCheckAnswerKey(Contract):
    """Guidance for the server: what prompts stay on the theme, and what the answer should
    cover. The wrong sentences are made per session, so they are not part of the key."""

    type: Literal["live_check"]
    topic_guide: NonEmptyText


class AgentAnswerKey(Contract):
    """What the agent needs to reach the goal, and what the mock tools return.
    Grading is deterministic: the run succeeds iff every required tool and rule is picked and
    no forbidden tool is. The model only narrates the run with these tool outputs."""

    type: Literal["agent"]
    required_tool_ids: list[Id] = Field(min_length=1)
    required_rule_ids: list[Id] = Field(default_factory=list)
    # Tools that must not be used for this goal (e.g. posting personal data).
    forbidden_tool_ids: list[Id] = Field(default_factory=list)
    # Fixed result of each mock tool, keyed by tool id.
    tool_outputs: dict[Id, NonEmptyText]
    explanation: NonEmptyText

    @model_validator(mode="after")
    def _consistent(self) -> Self:
        if set(self.required_tool_ids) & set(self.forbidden_tool_ids):
            raise ValueError("a tool cannot be both required and forbidden")
        if not set(self.required_tool_ids) <= self.tool_outputs.keys():
            raise ValueError("every required tool needs an output")
        return self


AnswerKey = Annotated[
    ChoiceAnswerKey
    | OrderAnswerKey
    | FillBlankAnswerKey
    | HallucinationAnswerKey
    | PromptAnswerKey
    | StoryAnswerKey
    | LiveCheckAnswerKey
    | AgentAnswerKey,
    Field(discriminator="type"),
]
