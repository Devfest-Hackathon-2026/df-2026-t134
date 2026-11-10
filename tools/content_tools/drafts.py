"""Draft files under content/drafts/: generated exercises waiting for a person's review.

    content/drafts/hallucination/<exerciseId>.yaml
        review:     model, generatedAt, sources and the original correct sentences
        exercise:   the HallucinationExercise, ready to move into a lesson file
        answerKey:  its HallucinationAnswerKey, ready to move into the .answers.yaml file

The loader only reads content/units/, so drafts are never validated as lessons or seeded.
"""

import datetime as dt
import re
from pathlib import Path

import yaml
from app.schemas.common import Contract
from app.schemas.content import HallucinationAnswerKey, HallucinationExercise
from pydantic import AwareDatetime, Field

from content_tools.hallucination import Draft
from content_tools.validate import key_mismatches
from content_tools.yaml_io import read_yaml

HEADER = """\
# AI が作った問題の下書き（未公開）。公開するまでの手順は content/drafts/README.md を参照。
# review.sources で事実を確かめ、exercise と answerKey を直してから content/units/ に移す。
"""


class SourceEntry(Contract):
    title: str
    uri: str


class Review(Contract):
    model: str
    generated_at: AwareDatetime
    sources: list[SourceEntry] = Field(min_length=1)
    correct_sentences: list[str] = Field(min_length=1)


class HallucinationDraftFile(Contract):
    review: Review
    exercise: HallucinationExercise
    answer_key: HallucinationAnswerKey


def next_exercise_id(drafts_dir: Path, lesson_id: str) -> str:
    """<lessonId>-d<n> with n after every draft of the lesson already in drafts_dir."""
    pattern = re.compile(rf"^{re.escape(lesson_id)}-d(\d+)\.yaml$")
    taken = [
        int(match.group(1))
        for path in (drafts_dir.iterdir() if drafts_dir.is_dir() else ())
        if (match := pattern.match(path.name))
    ]
    return f"{lesson_id}-d{max(taken, default=0) + 1}"


def write_draft(drafts_dir: Path, draft: Draft, model: str, generated_at: dt.datetime) -> Path:
    path = drafts_dir / f"{draft.exercise.id}.yaml"
    if path.exists():
        raise FileExistsError(f"{path} already exists")
    document = HallucinationDraftFile(
        review=Review(
            model=model,
            generated_at=generated_at,
            sources=[SourceEntry(title=s.title, uri=s.uri) for s in draft.sources],
            correct_sentences=list(draft.correct_sentences),
        ),
        exercise=draft.exercise,
        answer_key=draft.answer_key,
    )
    data = document.model_dump(mode="json", exclude_none=True)
    body = yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=1000)
    drafts_dir.mkdir(parents=True, exist_ok=True)
    path.write_text(HEADER + body, encoding="utf-8")
    read_draft(path)  # what was written must read back as a valid draft
    return path


def read_draft(path: Path) -> HallucinationDraftFile:
    """Parse a draft and check its answer key against its exercise (raises ValueError)."""
    document = HallucinationDraftFile.model_validate(read_yaml(path))
    problems = key_mismatches(document.exercise, document.answer_key)
    if problems:
        raise ValueError(f"{path}: {'; '.join(problems)}")
    return document
