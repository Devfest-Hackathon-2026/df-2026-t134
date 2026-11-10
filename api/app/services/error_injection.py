"""Rewriting sentences of a correct explanation with plausible errors (requirements §5.2).

Shared by the hallucination drafts of the content tools (Q2, fixed error types) and the live
check (Q10, the model picks the types that fit the sentences). The original sentence of every
rewritten one becomes its correction, so grading stays deterministic.
"""

import re
from collections import Counter
from collections.abc import Collection, Sequence
from typing import Annotated

from pydantic import Field, StringConstraints, field_validator

from app.ai import GenerationRequest, JsonGenerator
from app.schemas.common import Contract
from app.schemas.content import HallucinationErrorType

MIN_SENTENCES = 4
MAX_SENTENCES = 8
MAX_SENTENCE_LENGTH = 80
INJECT_TEMPERATURE = 0.7

ERROR_TYPE_GUIDES: dict[HallucinationErrorType, str] = {
    "number": "数値（大きさ・量・割合など）を、もっともらしい別の数値に変える",
    "date": "年や日付を、もっともらしい別の年や日付に変える",
    "name": "人名・地名・作品名などを、もっともらしい別の名前に変える",
    "fake_source": "存在しない本・論文・調査・機関を出典として書き加える"
    "（例:「〇〇大学の 2019 年の調査によると」）",
    "causality": "原因と結果の関係を、もっともらしいがまちがった説明に変える",
    "fact": "事実を、もっともらしいがまちがった内容に変える",
}

INJECT_INSTRUCTION = f"""\
あなたは、中学生・高校生が「AI のまちがい（ハルシネーション）」を見つける練習問題を作る編集者です。
正しい解説文のうち、指定された数の文を、指定された種類の誤りを含む文に書きかえます。
- 書きかえた文は、もとの文と同じくらいの長さで、もっともらしく、
  すぐにはまちがいと分からないようにします。
- 1 つの文には 1 つの誤りだけを入れます。書きかえない文は出力しません。
- index は書きかえる文の番号、errorType は入れた誤りの種類、wrongText は書きかえた文です。
- tip には、その誤りを見抜くために何を確かめればよいかを、中学生に向けて 1 文で書きます。
  正しい答えそのものは書きません。
- 誤りの種類ごとの書きかえ方:
{"\n".join(f"  - {name}: {guide}" for name, guide in ERROR_TYPE_GUIDES.items())}
"""

SentenceText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=2, max_length=MAX_SENTENCE_LENGTH)
]

# A heading or list item instead of a sentence: "# 光合成", "- 葉で…", "・葉で…", "1. 葉で…".
_NOT_A_SENTENCE = re.compile(r"^(?:[-・*•#]|\d+[.)．、])")


class Explanation(Contract):
    """A correct explanation as plain sentences, ready to have errors put in."""

    sentences: list[SentenceText] = Field(min_length=MIN_SENTENCES, max_length=MAX_SENTENCES)

    @field_validator("sentences")
    @classmethod
    def _plain_sentences(cls, sentences: list[str]) -> list[str]:
        for sentence in sentences:
            if _NOT_A_SENTENCE.match(sentence):
                raise ValueError(f"not a plain sentence: {sentence!r}")
        return sentences


class InjectedError(Contract):
    index: int = Field(ge=0)
    error_type: HallucinationErrorType
    wrong_text: SentenceText
    tip: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class Injection(Contract):
    """The JSON the model returns."""

    errors: list[InjectedError] = Field(min_length=1, max_length=3)


class InjectionRejected(Exception):
    """The model's rewrite does not match the request (count, types, indexes, unchanged)."""


def split_sentences(text: str) -> list[str]:
    """Sentences end at "。" or a line break. List markers stay, so Explanation rejects them."""
    return [part.strip() for part in re.findall(r"[^。\n]+。?", text) if part.strip()]


def inject_errors(
    generator: JsonGenerator,
    topic: str,
    sentences: Sequence[str],
    error_types: Sequence[HallucinationErrorType],
) -> Injection:
    """Rewrite one sentence per entry of error_types, with exactly those types.
    Raises InjectionRejected, AiUnavailable, AiBlocked."""
    wanted = "\n".join(f"- {error_type}" for error_type in error_types)
    injection = _generate(
        generator,
        topic,
        sentences,
        f"# 入れる誤り（{len(error_types)} 個。この種類どおりに）\n{wanted}",
    )
    if Counter(error.error_type for error in injection.errors) != Counter(error_types):
        found = [error.error_type for error in injection.errors]
        raise InjectionRejected(f"asked for errors {list(error_types)}, got {found}")
    _check_sentences(injection, sentences)
    return injection


def inject_fitting_errors(
    generator: JsonGenerator,
    topic: str,
    sentences: Sequence[str],
    count: int,
    allowed_types: Collection[HallucinationErrorType],
) -> Injection:
    """Rewrite exactly count sentences; the model picks, from allowed_types, the type that
    fits each sentence. Raises InjectionRejected, AiUnavailable, AiBlocked."""
    if not 1 <= count < len(sentences):
        raise ValueError("count must be at least 1 and smaller than the number of sentences")
    allowed = [name for name in ERROR_TYPE_GUIDES if name in allowed_types]
    if not allowed:
        raise ValueError("allowed_types must name at least one error type")
    choices = "\n".join(f"- {error_type}" for error_type in allowed)
    injection = _generate(
        generator,
        topic,
        sentences,
        f"# 入れる誤り（ちょうど {count} 個。種類は、書きかえる文に合うものを次から選ぶ）"
        f"\n{choices}",
    )
    if len(injection.errors) != count:
        raise InjectionRejected(f"asked for {count} errors, got {len(injection.errors)}")
    other = sorted({e.error_type for e in injection.errors if e.error_type not in allowed})
    if other:
        raise InjectionRejected(f"errors of types {other} were not allowed")
    _check_sentences(injection, sentences)
    return injection


def _generate(
    generator: JsonGenerator, topic: str, sentences: Sequence[str], wanted: str
) -> Injection:
    numbered = "\n".join(f"{index}: {sentence}" for index, sentence in enumerate(sentences))
    return generator.generate(
        GenerationRequest(
            system_instruction=INJECT_INSTRUCTION,
            contents=f"# テーマ\n{topic}\n\n# 正しい解説文（番号: 文）\n{numbered}\n\n{wanted}",
            temperature=INJECT_TEMPERATURE,
        ),
        Injection,
    )


def _check_sentences(injection: Injection, sentences: Sequence[str]) -> None:
    indexes = [error.index for error in injection.errors]
    if len(set(indexes)) != len(indexes):
        raise InjectionRejected(f"two errors in one sentence: {indexes}")
    for error in injection.errors:
        if error.index >= len(sentences):
            raise InjectionRejected(
                f"index {error.index} is outside the {len(sentences)} sentences"
            )
        if _without_spaces(error.wrong_text) == _without_spaces(sentences[error.index]):
            raise InjectionRejected(f"sentence {error.index} was not changed")


def _without_spaces(text: str) -> str:
    return re.sub(r"\s+", "", text)
