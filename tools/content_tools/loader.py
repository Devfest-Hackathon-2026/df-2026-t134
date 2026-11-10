"""Read content/units/** into contract models, keeping the file each item came from.

Layout (see content/README.md):
    content/units/<unitId>/unit.yaml                 -> Unit
    content/units/<unitId>/<lessonId>.yaml           -> {lesson: Lesson, exercises: [Exercise]}
    content/units/<unitId>/<lessonId>.answers.yaml   -> {exerciseId: AnswerKey}

Only per-file (schema) problems are found here; cross-file checks live in validate.py.
"""

from dataclasses import dataclass
from pathlib import Path

from app.schemas.common import Id
from app.schemas.content import AnswerKey, Exercise, Lesson, Unit
from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

from content_tools.yaml_io import YamlError, read_yaml

UNIT_FILE = "unit.yaml"
LESSON_SUFFIX = ".yaml"
ANSWERS_SUFFIX = ".answers.yaml"


@dataclass(frozen=True)
class Problem:
    path: Path
    message: str

    def __str__(self) -> str:
        return f"{self.path}: {self.message}"


@dataclass(frozen=True)
class UnitFile:
    path: Path
    unit: Unit


@dataclass(frozen=True)
class LessonFile:
    path: Path
    lesson: Lesson
    exercises: tuple[Exercise, ...]


@dataclass(frozen=True)
class AnswersFile:
    path: Path
    keys: dict[str, AnswerKey]


@dataclass(frozen=True)
class Content:
    units: tuple[UnitFile, ...]
    lessons: tuple[LessonFile, ...]
    answers: tuple[AnswersFile, ...]


@dataclass(frozen=True)
class Loaded:
    content: Content
    problems: tuple[Problem, ...]


class _LessonDocument(BaseModel):
    """Top level of a lesson file. The item models themselves are the shared contracts."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    lesson: Lesson
    exercises: list[Exercise]


_unit_adapter = TypeAdapter(Unit)
_lesson_adapter = TypeAdapter(_LessonDocument)
_answers_adapter = TypeAdapter(dict[Id, AnswerKey])


def folder_of(path: Path) -> str:
    """The unit folder name of a content file."""
    return path.parent.name


def lesson_id_of(path: Path) -> str:
    """The lesson id that a lesson or answers file name declares."""
    name = path.name
    suffix = ANSWERS_SUFFIX if name.endswith(ANSWERS_SUFFIX) else LESSON_SUFFIX
    return name.removesuffix(suffix)


def answers_path_for(lesson_path: Path) -> Path:
    return lesson_path.with_name(lesson_id_of(lesson_path) + ANSWERS_SUFFIX)


def load_content(root: Path) -> Loaded:
    """Parse every content file under root/units. Problems are collected, not raised."""
    units_dir = root / "units"
    if not units_dir.is_dir():
        return Loaded(Content((), (), ()), (Problem(units_dir, "directory not found"),))

    problems: list[Problem] = []
    units: list[UnitFile] = []
    lessons: list[LessonFile] = []
    answers: list[AnswersFile] = []

    for unit_dir in _visible_children(units_dir):
        if not unit_dir.is_dir():
            problems.append(Problem(unit_dir, "unexpected file; units/ holds one folder per unit"))
            continue
        unit_path = unit_dir / UNIT_FILE
        if not unit_path.is_file():
            problems.append(Problem(unit_path, "missing unit file"))
        for path in _visible_children(unit_dir):
            if path.name == UNIT_FILE:
                unit = _parse(path, _unit_adapter, problems)
                if unit is not None:
                    units.append(UnitFile(path, unit))
            elif path.is_file() and path.name.endswith(ANSWERS_SUFFIX):
                keys = _parse(path, _answers_adapter, problems)
                if keys is not None:
                    answers.append(AnswersFile(path, keys))
            elif path.is_file() and path.name.endswith(LESSON_SUFFIX):
                document = _parse(path, _lesson_adapter, problems)
                if document is not None:
                    lessons.append(LessonFile(path, document.lesson, tuple(document.exercises)))
            else:
                problems.append(
                    Problem(
                        path,
                        "unexpected entry; expected unit.yaml, <lessonId>.yaml "
                        "or <lessonId>.answers.yaml",
                    )
                )

    return Loaded(Content(tuple(units), tuple(lessons), tuple(answers)), tuple(problems))


def _visible_children(directory: Path) -> list[Path]:
    return sorted(p for p in directory.iterdir() if not p.name.startswith("."))


def _parse[T](path: Path, adapter: TypeAdapter[T], problems: list[Problem]) -> T | None:
    try:
        data = read_yaml(path)
    except YamlError as error:
        problems.append(Problem(path, f"invalid YAML: {error}"))
        return None
    if data is None:
        problems.append(Problem(path, "file is empty"))
        return None
    try:
        return adapter.validate_python(data)
    except ValidationError as error:
        for detail in error.errors():
            location = ".".join(str(part) for part in detail["loc"]) or "(root)"
            problems.append(Problem(path, f"{location}: {detail['msg']}"))
        return None
