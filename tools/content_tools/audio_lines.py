"""Fixed lines as pre-generated audio (§5.4): the mascot's lesson and exercise intros, and
every line of the story scenes, each in the voice of its speaker.

`speak` synthesizes every line into Cloud Storage (audio/lines/<hash>.mp3, shared cache with
the API) and writes content/audio/lines.yaml: one entry per (speaker, text) with its audio
path. `seed` fills Speech.audioPath and Scene.audioPath from that file, so the YAML under
content/units/ never carries generated paths (and validation rejects one written by hand).
"""

from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Protocol, Self

import yaml
from app.ai import AiUnavailable
from app.schemas.common import Contract, NonEmptyText
from app.schemas.content import Scene, Speaker, Speech
from pydantic import Field, StringConstraints, ValidationError, model_validator

from content_tools.loader import Content, LessonFile, Problem
from content_tools.scenes import all_scenes, map_scenes
from content_tools.yaml_io import YamlError, read_yaml

LINES_AUDIO_PREFIX = "audio/lines/"
AUDIO_LINES_FILE = Path("audio") / "lines.yaml"

HEADER = """\
# `make speak` が書き出すファイル（手で編集しない）。固定セリフ（話す人ごと）と、その音声の保存先。
# `make seed` がこの対応表から教材の intro.audioPath と紙しばいの場面の audioPath を埋める。
"""

# Intros are always spoken by the mascot.
INTRO_SPEAKER: Speaker = "mascot"

LinesAudioPath = Annotated[str, StringConstraints(pattern=r"^audio/lines/[0-9a-f]{64}\.mp3$")]


@dataclass(frozen=True)
class VoiceLine:
    """A text in the voice of a speaker (the same text by two speakers sounds different)."""

    speaker: Speaker
    text: str


class AudioLine(Contract):
    speaker: Speaker = INTRO_SPEAKER
    text: NonEmptyText
    audio_path: LinesAudioPath

    @property
    def line(self) -> VoiceLine:
        return VoiceLine(self.speaker, self.text)


class AudioLinesFile(Contract):
    lines: list[AudioLine] = Field(default_factory=list)

    @model_validator(mode="after")
    def _unique_lines(self) -> Self:
        lines = [line.line for line in self.lines]
        if len(set(lines)) != len(lines):
            raise ValueError("each (speaker, text) must appear once")
        return self

    def paths_by_line(self) -> dict[VoiceLine, str]:
        return {line.line: line.audio_path for line in self.lines}


@dataclass(frozen=True)
class SpokenLine:
    path: Path  # the lesson or answers file it comes from
    where: str  # e.g. "lesson u1-l1", "exercise u1-l1-q2" or "exercise u1-l4-q1 scenes[0]"
    field: str  # where the generated path goes: "intro.audioPath" or "audioPath"
    line: VoiceLine
    audio_path: str | None


def spoken_lines(content: Content) -> list[SpokenLine]:
    """Every intro, then every story scene, in file order."""
    lines: list[SpokenLine] = []
    for file in content.lessons:
        intros = [(f"lesson {file.lesson.id}", file.lesson.intro)]
        intros += [(f"exercise {exercise.id}", exercise.intro) for exercise in file.exercises]
        lines += [
            SpokenLine(
                file.path,
                where,
                "intro.audioPath",
                VoiceLine(INTRO_SPEAKER, intro.text),
                intro.audio_path,
            )
            for where, intro in intros
            if intro is not None
        ]
    lines += [
        SpokenLine(
            located.path,
            located.where,
            "audioPath",
            VoiceLine(located.scene.speaker, located.scene.text),
            located.scene.audio_path,
        )
        for located in all_scenes(content)
    ]
    return lines


def hand_written_audio_paths(content: Content) -> list[Problem]:
    return [
        Problem(
            line.path,
            f"{line.where}: {line.field} is filled in from {AUDIO_LINES_FILE} by `make speak`;"
            " remove it",
        )
        for line in spoken_lines(content)
        if line.audio_path is not None
    ]


def unique_lines(content: Content) -> list[VoiceLine]:
    return list(dict.fromkeys(line.line for line in spoken_lines(content)))


def read_audio_lines(root: Path) -> tuple[AudioLinesFile, list[Problem]]:
    """root/audio/lines.yaml, or an empty file when it does not exist yet."""
    path = root / AUDIO_LINES_FILE
    if not path.exists():
        return AudioLinesFile(), []
    try:
        return AudioLinesFile.model_validate(read_yaml(path)), []
    except (YamlError, ValidationError) as error:
        return AudioLinesFile(), [Problem(path, str(error))]


def write_audio_lines(root: Path, lines: Iterable[AudioLine]) -> Path:
    path = root / AUDIO_LINES_FILE
    document = AudioLinesFile(lines=list(lines))
    body = yaml.safe_dump(
        document.model_dump(mode="json"), allow_unicode=True, sort_keys=False, width=1000
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(HEADER + body, encoding="utf-8")
    return path


def with_audio(content: Content, paths_by_line: Mapping[VoiceLine, str]) -> Content:
    """Content whose intros and story scenes carry the audio path of their line, when it has
    one (a line without audio yet is shown as text only)."""

    def speech(intro: Speech | None) -> Speech | None:
        path = None if intro is None else paths_by_line.get(VoiceLine(INTRO_SPEAKER, intro.text))
        if intro is None or path is None:
            return intro
        return Speech(text=intro.text, audio_path=path)

    def scene(item: Scene) -> Scene:
        path = paths_by_line.get(VoiceLine(item.speaker, item.text))
        return item if path is None else item.model_copy(update={"audio_path": path})

    def lesson_file(file: LessonFile) -> LessonFile:
        lesson = file.lesson.model_copy(update={"intro": speech(file.lesson.intro)})
        exercises = tuple(
            exercise.model_copy(update={"intro": speech(exercise.intro)})
            for exercise in file.exercises
        )
        return LessonFile(file.path, lesson, exercises)

    intros = Content(content.units, tuple(lesson_file(f) for f in content.lessons), content.answers)
    return map_scenes(intros, scene)


class LineSpeech(Protocol):
    def audio_path_for(self, text: str) -> str:
        """Storage path of the audio of text. Raises AiUnavailable when no voice can speak."""
        ...


def speak(
    speech_of: Callable[[Speaker], LineSpeech], lines: Iterable[VoiceLine]
) -> tuple[list[AudioLine], list[VoiceLine]]:
    """Audio for every line in its speaker's voice, and the lines no voice could speak (to
    run again)."""
    spoken: list[AudioLine] = []
    failed: list[VoiceLine] = []
    for line in lines:
        try:
            path = speech_of(line.speaker).audio_path_for(line.text)
        except AiUnavailable:
            failed.append(line)
            continue
        spoken.append(AudioLine(speaker=line.speaker, text=line.text, audio_path=path))
    return spoken, failed
