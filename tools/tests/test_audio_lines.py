"""Pre-generated audio of the mascot's lines: collecting, validating, seeding and `speak`."""

from collections.abc import Callable
from pathlib import Path

import pytest
from app.ai import AiUnavailable
from app.speech_cache import audio_path

from content_tools import __main__ as cli
from content_tools.audio_lines import (
    AUDIO_LINES_FILE,
    LINES_AUDIO_PREFIX,
    AudioLine,
    VoiceLine,
    read_audio_lines,
    speak,
    unique_lines,
    with_audio,
    write_audio_lines,
)
from content_tools.seed import build_documents
from content_tools.validate import validate_content
from tests.conftest import Tree, valid_tree

LESSON_FILE = "units/u9/u9-l1.yaml"
LESSON_INTRO = "はじめよう"
EXERCISE_INTRO = "まずはこの問題から"


def _path(text: str) -> str:
    return audio_path(LINES_AUDIO_PREFIX, "test-voice", text)


def _tree_with_intros() -> Tree:
    tree = valid_tree()
    exercises = tree[LESSON_FILE]["exercises"]
    exercises[0]["intro"] = {"text": EXERCISE_INTRO}
    exercises[1]["intro"] = {"text": LESSON_INTRO}  # the same line twice is spoken once
    return tree


class FakeSpeech:
    def __init__(self, failing: frozenset[str] = frozenset()) -> None:
        self.failing = failing
        self.spoken: list[str] = []

    def audio_path_for(self, text: str) -> str:
        self.spoken.append(text)
        if text in self.failing:
            raise AiUnavailable("no voice")
        return _path(text)


def test_every_intro_is_spoken_once_in_file_order(make_content: Callable[[Tree], Path]) -> None:
    report = validate_content(make_content(_tree_with_intros()))

    assert report.ok, report.problems
    assert unique_lines(report.content) == [
        VoiceLine("mascot", LESSON_INTRO),
        VoiceLine("mascot", EXERCISE_INTRO),
    ]


def test_speak_reports_lines_no_voice_could_speak() -> None:
    speech = FakeSpeech(failing=frozenset({EXERCISE_INTRO}))

    lines = [VoiceLine("mascot", LESSON_INTRO), VoiceLine("mascot", EXERCISE_INTRO)]
    spoken, failed = speak(lambda speaker: speech, lines)

    assert spoken == [AudioLine(text=LESSON_INTRO, audio_path=_path(LESSON_INTRO))]
    assert failed == [VoiceLine("mascot", EXERCISE_INTRO)]


def test_seeded_intros_carry_the_audio_of_their_text(make_content: Callable[[Tree], Path]) -> None:
    root = make_content(_tree_with_intros())
    write_audio_lines(root, [AudioLine(text=LESSON_INTRO, audio_path=_path(LESSON_INTRO))])
    report = validate_content(root)
    audio, problems = read_audio_lines(root)
    assert report.ok and not problems

    docs = build_documents(with_audio(report.content, audio.paths_by_line()))

    assert docs["lessons"]["u9-l1"]["intro"] == {
        "text": LESSON_INTRO,
        "audioPath": _path(LESSON_INTRO),
    }
    assert docs["exercises"]["u9-l1-q2"]["intro"]["audioPath"] == _path(LESSON_INTRO)
    # A line without audio yet is seeded as text only (the app shows the subtitle).
    assert docs["exercises"]["u9-l1-q1"]["intro"] == {"text": EXERCISE_INTRO}


def test_audio_lines_file_round_trips(tmp_path: Path) -> None:
    lines = [AudioLine(text="一行目\n二行目", audio_path=_path("一行目\n二行目"))]

    path = write_audio_lines(tmp_path, lines)
    audio, problems = read_audio_lines(tmp_path)

    assert path == tmp_path / AUDIO_LINES_FILE
    assert path.read_text(encoding="utf-8").startswith("# `make speak`")
    assert problems == []
    assert audio.lines == lines


def test_missing_audio_lines_file_means_no_audio_yet(tmp_path: Path) -> None:
    audio, problems = read_audio_lines(tmp_path)

    assert (audio.lines, problems) == ([], [])


def test_audio_path_written_by_hand_is_rejected(make_content: Callable[[Tree], Path]) -> None:
    tree = valid_tree()
    tree[LESSON_FILE]["lesson"]["intro"]["audioPath"] = "audio/lines/hand.mp3"

    report = validate_content(make_content(tree))

    [problem] = report.problems
    assert problem.path.name == "u9-l1.yaml"
    assert "lesson u9-l1: intro.audioPath is filled in from audio/lines.yaml" in problem.message


@pytest.mark.parametrize(
    "text",
    [
        "lines:\n  - text: x\n    audioPath: audio/feedback/x.mp3\n",
        "lines:\n  - text: x\n    audioPath: audio/lines/" + "a" * 64 + ".mp3\n"
        "  - text: x\n    audioPath: audio/lines/" + "b" * 64 + ".mp3\n",
        "lines:\n  - speaker: robot\n    text: x\n    audioPath: audio/lines/"
        + "a" * 64
        + ".mp3\n",
        "lines:\n  - text: x\n    path: audio/lines/" + "a" * 64 + ".mp3\n",
        "lines: [\n",
    ],
    ids=["outside audio/lines", "duplicate text", "unknown speaker", "unknown key", "broken yaml"],
)
def test_broken_audio_lines_file_fails_validation(
    make_content: Callable[[Tree], Path], text: str
) -> None:
    root = make_content(valid_tree())
    (root / AUDIO_LINES_FILE).parent.mkdir()
    (root / AUDIO_LINES_FILE).write_text(text, encoding="utf-8")

    report = validate_content(root)

    [problem] = report.problems
    assert problem.path == root / AUDIO_LINES_FILE


def test_speak_command_writes_what_it_spoke_and_fails_for_the_rest(
    make_content: Callable[[Tree], Path],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    root = make_content(_tree_with_intros())
    for name, value in [("TTS_MODEL", "m"), ("STORAGE_BUCKET", "b"), ("FIREBASE_PROJECT_ID", "p")]:
        monkeypatch.setenv(name, value)
    speech = FakeSpeech(failing=frozenset({EXERCISE_INTRO}))
    monkeypatch.setattr(cli.firebase_admin, "initialize_app", lambda **kwargs: object())
    monkeypatch.setattr(cli, "firebase_bucket", lambda app, name: object())
    monkeypatch.setattr(cli, "tts_client", lambda: object())
    monkeypatch.setattr(cli, "CachedSpeech", lambda store, voices, prefix: speech)

    with pytest.raises(SystemExit, match="no voice could speak 1 line"):
        cli.main(["speak", str(root)])

    audio, _ = read_audio_lines(root)
    assert audio.paths_by_line() == {VoiceLine("mascot", LESSON_INTRO): _path(LESSON_INTRO)}
    assert speech.spoken == [LESSON_INTRO, EXERCISE_INTRO]
    assert f"NO AUDIO mascot: {EXERCISE_INTRO!r}" in capsys.readouterr().err


def test_speak_command_needs_the_tts_settings(
    make_content: Callable[[Tree], Path], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("TTS_MODEL", raising=False)

    with pytest.raises(SystemExit, match="TTS_MODEL is not set"):
        cli.main(["speak", str(make_content(valid_tree()))])
