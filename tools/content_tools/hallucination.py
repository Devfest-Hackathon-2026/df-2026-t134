"""Draft hallucination exercises (Q2) with Gemini (requirements §5.2 and §14 R4).

1. A short, correct explanation of the topic is written with Google Search grounding.
2. A second request rewrites some of its sentences with errors of the requested types
   (JSON schema). The original sentence becomes the correction, so the answer key is fixed
   when the exercise is made and grading stays deterministic.
3. The draft is checked like published content and written as YAML under content/drafts/,
   with its sources, for a person to check before it is moved into a lesson. Nothing here
   publishes anything.
"""

from collections.abc import Sequence
from dataclasses import dataclass

from app.ai import GenerationRequest, GroundedWriter, JsonGenerator, Source
from app.schemas.common import Id
from app.schemas.content import (
    HallucinationAnswerKey,
    HallucinationError,
    HallucinationErrorType,
    HallucinationExercise,
    Sentence,
)

# The rewriting core is shared with the API's live check (api/app/services/error_injection.py).
from app.services.error_injection import (
    ERROR_TYPE_GUIDES,
    INJECT_INSTRUCTION,
    MAX_SENTENCE_LENGTH,
    MAX_SENTENCES,
    MIN_SENTENCES,
    Explanation,
    InjectedError,
    Injection,
    InjectionRejected,
    split_sentences,
)
from app.services.error_injection import inject_errors as _inject_errors
from pydantic import TypeAdapter, ValidationError

from content_tools.validate import key_mismatches

__all__ = [
    "ERROR_TYPE_GUIDES",
    "INJECT_INSTRUCTION",
    "QUESTION",
    "WRITE_INSTRUCTION",
    "Draft",
    "DraftRejected",
    "Explanation",
    "InjectedError",
    "Injection",
    "draft_exercise",
    "inject_errors",
    "split_sentences",
    "write_explanation",
]

WRITE_TEMPERATURE = 0.3

QUESTION = "AI の答えの中に、まちがっている文があります。まちがっている文をすべてタップしよう。"

WRITE_INSTRUCTION = f"""\
あなたは、中学生・高校生向けの教材を作る編集者です。Google 検索で確かめた事実だけを使い、
指定されたテーマについて、AI アシスタントが答えるような短い解説を書きます。
- {MIN_SENTENCES}〜{MAX_SENTENCES} 文で書きます。1 行に 1 文だけ書き、文の終わりは「。」にします。
- 中学 1 年生が読める言葉で、1 文は {MAX_SENTENCE_LENGTH // 2} 文字くらいまでにします。
- 数値・年・人名・地名など、確かめられる具体的な事実を多めに入れます。
- 見出し・箇条書きの記号・番号・出典の表記は書きません。
"""


class DraftRejected(Exception):
    """The model's output cannot become an exercise (wrong shape, count, types or indexes)."""


@dataclass(frozen=True, slots=True)
class Draft:
    exercise: HallucinationExercise
    answer_key: HallucinationAnswerKey
    correct_sentences: tuple[str, ...]
    sources: tuple[Source, ...]


_id = TypeAdapter(Id)


def write_explanation(writer: GroundedWriter, topic: str) -> tuple[Explanation, tuple[Source, ...]]:
    grounded = writer.write(
        GenerationRequest(
            system_instruction=WRITE_INSTRUCTION,
            contents=f"テーマ: {topic}",
            temperature=WRITE_TEMPERATURE,
        )
    )
    try:
        explanation = Explanation(sentences=split_sentences(grounded.text))
    except ValidationError as exc:
        raise DraftRejected(f"explanation does not have the expected sentences: {exc}") from exc
    return explanation, grounded.sources


def inject_errors(
    generator: JsonGenerator,
    topic: str,
    sentences: Sequence[str],
    error_types: Sequence[HallucinationErrorType],
) -> Injection:
    try:
        return _inject_errors(generator, topic, sentences, error_types)
    except InjectionRejected as exc:
        raise DraftRejected(str(exc)) from exc


def draft_exercise(
    writer: GroundedWriter,
    generator: JsonGenerator,
    exercise_id: str,
    lesson_id: str,
    topic: str,
    error_types: Sequence[HallucinationErrorType],
) -> Draft:
    """Write, inject and check one exercise. Raises DraftRejected, AiUnavailable, AiBlocked."""
    if not exercise_id.startswith(f"{_id.validate_python(lesson_id)}-"):
        raise ValueError("exercise_id must start with the lesson id")
    if not 1 <= len(error_types) <= 3:
        raise ValueError("an exercise has 1 to 3 errors")
    explanation, sources = write_explanation(writer, topic)
    correct = explanation.sentences
    injection = inject_errors(generator, topic, correct, error_types)
    wrong = {error.index: error.wrong_text for error in injection.errors}
    exercise = HallucinationExercise(
        id=exercise_id,
        lesson_id=lesson_id,
        type="hallucination",
        question=QUESTION,
        topic=topic,
        sentences=[
            Sentence(index=index, text=wrong.get(index, sentence))
            for index, sentence in enumerate(correct)
        ],
        error_count=len(injection.errors),
    )
    answer_key = HallucinationAnswerKey(
        type="hallucination",
        errors=[
            HallucinationError(
                index=error.index,
                error_type=error.error_type,
                correction=correct[error.index],
                tip=error.tip,
            )
            for error in sorted(injection.errors, key=lambda error: error.index)
        ],
    )
    # The same cross-check as `make content-validate`, so a draft can be published as is.
    problems = key_mismatches(exercise, answer_key)
    if problems:
        raise DraftRejected("; ".join(problems))
    return Draft(exercise, answer_key, tuple(correct), sources)
