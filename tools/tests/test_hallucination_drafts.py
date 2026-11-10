"""Drafting hallucination exercises with a fake Gemini (no network, no credentials)."""

import datetime as dt
from collections.abc import Iterator
from pathlib import Path

import pytest
import yaml
from app.ai import AiUnavailable, GenerationRequest, GroundedText, Source
from app.schemas.content import HallucinationErrorType
from pydantic import BaseModel

from content_tools import __main__ as cli
from content_tools.drafts import HEADER, next_exercise_id, read_draft, write_draft
from content_tools.hallucination import (
    INJECT_INSTRUCTION,
    QUESTION,
    WRITE_INSTRUCTION,
    DraftRejected,
    InjectedError,
    Injection,
    draft_exercise,
    split_sentences,
)

CORRECT = [
    "富士山は日本でいちばん高い山です。",
    "高さは 3776 メートルです。",
    "静岡県と山梨県にまたがっています。",
    "2013 年に世界文化遺産になりました。",
]
EXPLANATION = "\n".join(CORRECT)
SOURCES = (Source(title="example.jp", uri="https://example.jp/fuji"),)
GENERATED_AT = dt.datetime(2026, 11, 9, 1, 0, tzinfo=dt.UTC)


class FakeWriter:
    def __init__(self, text: str = EXPLANATION, sources: tuple[Source, ...] = SOURCES) -> None:
        self.result = GroundedText(text=text, sources=sources)
        self.requests: list[GenerationRequest] = []

    def write(self, request: GenerationRequest) -> GroundedText:
        self.requests.append(request)
        return self.result


class FakeGenerator:
    def __init__(self, output: BaseModel | Exception) -> None:
        self.output = output
        self.requests: list[GenerationRequest] = []

    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        self.requests.append(request)
        if isinstance(self.output, Exception):
            raise self.output
        assert isinstance(self.output, schema)
        return self.output


def _error(index: int, error_type: HallucinationErrorType, text: str) -> InjectedError:
    return InjectedError(index=index, error_type=error_type, wrong_text=text, tip=f"tip {index}")


INJECTION = Injection(
    errors=[
        _error(3, "date", "2003 年に世界文化遺産になりました。"),
        _error(1, "number", "高さは 5776 メートルです。"),
    ]
)
ERROR_TYPES: list[HallucinationErrorType] = ["number", "date"]


def _draft(
    writer: FakeWriter | None = None,
    generator: FakeGenerator | None = None,
    error_types: list[HallucinationErrorType] = ERROR_TYPES,
):
    return draft_exercise(
        writer or FakeWriter(),
        generator or FakeGenerator(INJECTION),
        "u3-l1-d1",
        "u3-l1",
        "富士山",
        error_types,
    )


def test_wrong_sentences_replace_the_correct_ones_which_become_the_corrections() -> None:
    draft = _draft()

    exercise, key = draft.exercise, draft.answer_key
    assert (exercise.id, exercise.lesson_id, exercise.topic) == ("u3-l1-d1", "u3-l1", "富士山")
    assert exercise.question == QUESTION
    assert [s.text for s in exercise.sentences] == [
        CORRECT[0],
        "高さは 5776 メートルです。",
        CORRECT[2],
        "2003 年に世界文化遺産になりました。",
    ]
    assert exercise.error_count == 2
    assert [(e.index, e.error_type, e.correction, e.tip) for e in key.errors] == [
        (1, "number", CORRECT[1], "tip 1"),
        (3, "date", CORRECT[3], "tip 3"),
    ]
    assert draft.correct_sentences == tuple(CORRECT)
    assert draft.sources == SOURCES


def test_model_is_asked_for_grounded_facts_then_for_the_requested_errors() -> None:
    writer, generator = FakeWriter(), FakeGenerator(INJECTION)

    _draft(writer, generator)

    [write] = writer.requests
    assert write.system_instruction == WRITE_INSTRUCTION
    assert write.contents == "テーマ: 富士山"
    [inject] = generator.requests
    assert inject.system_instruction == INJECT_INSTRUCTION
    assert "1: 高さは 3776 メートルです。" in inject.contents
    assert inject.contents.endswith("- number\n- date")


@pytest.mark.parametrize(
    ("text", "sentences"),
    [
        ("一文目。二文目。\n三文目。", ["一文目。", "二文目。", "三文目。"]),
        ("  一文目\n\n二文目。  ", ["一文目", "二文目。"]),
    ],
)
def test_explanation_is_split_into_sentences(text: str, sentences: list[str]) -> None:
    assert split_sentences(text) == sentences


@pytest.mark.parametrize(
    "text",
    [
        "一文目。二文目。",  # too few
        "\n".join(f"{n} 文目です。" for n in range(1, 10)),  # too many
        "# 富士山\n" + EXPLANATION,
        "\n".join(f"- {sentence}" for sentence in CORRECT),
        "\n".join(f"{n}. {sentence}" for n, sentence in enumerate(CORRECT, 1)),
        EXPLANATION + "\n" + "とても" * 50 + "長い文です。",
    ],
    ids=["too few", "too many", "heading", "bullets", "numbered", "too long"],
)
def test_explanation_that_is_not_plain_sentences_is_rejected(text: str) -> None:
    with pytest.raises(DraftRejected, match="explanation"):
        _draft(writer=FakeWriter(text=text))


@pytest.mark.parametrize(
    ("errors", "message"),
    [
        ([_error(1, "number", "高さは 5776 メートルです。")], "asked for errors"),
        (
            [_error(1, "number", "高さは 5776 m。"), _error(3, "name", "2003 年に…。")],
            "asked for errors",
        ),
        ([_error(1, "number", "高さは 5776 m。"), _error(1, "date", "x年。")], "two errors"),
        ([_error(1, "number", "高さは 5776 m。"), _error(9, "date", "x年。")], "outside"),
        ([_error(1, "number", CORRECT[1]), _error(3, "date", "x年。")], "not changed"),
    ],
    ids=["too few", "other type", "same sentence", "out of range", "unchanged"],
)
def test_injection_that_does_not_match_the_request_is_rejected(
    errors: list[InjectedError], message: str
) -> None:
    with pytest.raises(DraftRejected, match=message):
        _draft(generator=FakeGenerator(Injection(errors=errors)))


def test_model_failures_are_passed_on() -> None:
    with pytest.raises(AiUnavailable):
        _draft(generator=FakeGenerator(AiUnavailable("timed out")))


@pytest.mark.parametrize(
    ("exercise_id", "lesson_id", "error_types"),
    [
        ("u3-l2-d1", "u3-l1", ERROR_TYPES),
        ("u3-l1-d1", "U3", ERROR_TYPES),
        ("u3-l1-d1", "u3-l1", ["number", "date", "name", "fact"]),
    ],
    ids=["id of another lesson", "invalid lesson id", "four errors"],
)
def test_invalid_arguments_fail_before_calling_the_model(
    exercise_id: str, lesson_id: str, error_types: list[HallucinationErrorType]
) -> None:
    writer = FakeWriter()

    with pytest.raises(ValueError):
        draft_exercise(
            writer, FakeGenerator(INJECTION), exercise_id, lesson_id, "富士山", error_types
        )
    assert writer.requests == []


def test_draft_file_reads_back_as_a_publishable_exercise(tmp_path: Path) -> None:
    draft = _draft()

    path = write_draft(tmp_path, draft, "test-model", GENERATED_AT)

    assert path == tmp_path / "u3-l1-d1.yaml"
    text = path.read_text(encoding="utf-8")
    assert text.startswith(HEADER)
    assert "富士山は日本でいちばん高い山です。" in text  # readable Japanese, not escapes
    document = read_draft(path)
    assert document.exercise == draft.exercise
    assert document.answer_key == draft.answer_key
    assert document.review.model == "test-model"
    assert document.review.generated_at == GENERATED_AT
    assert [s.uri for s in document.review.sources] == ["https://example.jp/fuji"]
    assert list(yaml.safe_load(text)) == ["review", "exercise", "answerKey"]


def test_existing_draft_is_never_overwritten(tmp_path: Path) -> None:
    write_draft(tmp_path, _draft(), "test-model", GENERATED_AT)

    with pytest.raises(FileExistsError):
        write_draft(tmp_path, _draft(), "test-model", GENERATED_AT)


def test_edited_draft_that_no_longer_matches_is_rejected(tmp_path: Path) -> None:
    path = write_draft(tmp_path, _draft(), "test-model", GENERATED_AT)
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    data["exercise"]["errorCount"] = 1
    path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")

    with pytest.raises(ValueError, match="errorCount"):
        read_draft(path)


def test_draft_ids_continue_after_the_lessons_existing_drafts(tmp_path: Path) -> None:
    assert next_exercise_id(tmp_path / "missing", "u3-l1") == "u3-l1-d1"
    for name in ("u3-l1-d1.yaml", "u3-l1-d7.yaml", "u3-l10-d9.yaml", "notes.yaml"):
        (tmp_path / name).write_text("x")

    assert next_exercise_id(tmp_path, "u3-l1") == "u3-l1-d8"
    assert next_exercise_id(tmp_path, "u3-l2") == "u3-l2-d1"


def test_command_drafts_each_topic_and_reports_the_ones_that_failed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("GEMINI_MODEL", "test-model")
    monkeypatch.setenv("VERTEX_PROJECT", "test-project")
    monkeypatch.setattr(cli, "vertex_models", lambda project, location, timeout: object())
    monkeypatch.setattr(cli, "GeminiGroundedWriter", lambda models, model: FakeWriter())
    # The second topic gets an injection that leaves its sentence unchanged.
    outputs = iter([INJECTION, Injection(errors=[_error(1, "number", CORRECT[1])])])
    monkeypatch.setattr(cli, "GeminiJsonGenerator", lambda models, model: _Sequence(outputs))

    with pytest.raises(SystemExit, match="no draft for 1 topic"):
        cli.main(
            ["draft-hallucination", str(tmp_path), "--lesson", "u3-l1", "--topic", "富士山",
             "--topic", "琵琶湖", "--error-type", "number", "--error-type", "date"]
        )  # fmt: skip

    assert [p.name for p in tmp_path.iterdir()] == ["u3-l1-d1.yaml"]
    assert "SKIP 琵琶湖: DraftRejected" in capsys.readouterr().err


def test_command_needs_the_gemini_settings(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("GEMINI_MODEL", raising=False)

    with pytest.raises(SystemExit, match="GEMINI_MODEL is not set"):
        cli.main(["draft-hallucination", str(tmp_path), "--lesson", "u3-l1", "--topic", "x"])


class _Sequence:
    """A generator that returns the next queued output on every call."""

    def __init__(self, outputs: Iterator[BaseModel]) -> None:
        self.outputs = outputs

    def generate[T: BaseModel](self, request: GenerationRequest, schema: type[T]) -> T:
        output = next(self.outputs)
        assert isinstance(output, schema)
        return output


def test_clean_draft_has_no_errors_and_never_calls_the_rewriter():
    generator = FakeGenerator(AiUnavailable("clean drafts must not call the rewriter"))
    draft = _draft(generator=generator, error_types=[])
    assert generator.requests == []
    assert draft.exercise.error_count == 0
    assert draft.answer_key.errors == []
    assert [sentence.text for sentence in draft.exercise.sentences] == list(draft.correct_sentences)
