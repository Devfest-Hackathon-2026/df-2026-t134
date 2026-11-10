"""The real content/ of this repository (mounted next to tools/ in the container)."""

from pathlib import Path

import pytest
from app.schemas.content import StoryAnswerKey, StoryExercise

from content_tools.__main__ import main
from content_tools.validate import validate_content

CONTENT_DIR = Path(__file__).resolve().parents[2] / "content"
STORY_LESSON_ID = "u1-l4"


def test_repo_content_is_valid() -> None:
    report = validate_content(CONTENT_DIR)

    assert [str(p) for p in report.problems] == []
    assert report.content.units, "content/units has no units"


def test_unit_1_uses_only_q1_and_q3_types() -> None:
    lessons = [
        f
        for f in validate_content(CONTENT_DIR).content.lessons
        if f.lesson.unit_id == "u1" and f.lesson.id != STORY_LESSON_ID
    ]

    assert len(lessons) == 3
    for lesson_file in lessons:
        assert 5 <= len(lesson_file.exercises) <= 7
        assert lesson_file.lesson.intro is not None
        assert {e.type for e in lesson_file.exercises} <= {"choice", "order", "fill_blank"}


def test_unit_1_story_lesson_comes_after_the_basics() -> None:
    content = validate_content(CONTENT_DIR).content
    [story] = [f for f in content.lessons if f.lesson.id == STORY_LESSON_ID]
    others = [f.lesson.order for f in content.lessons if f.lesson.unit_id == "u1"]

    assert story.lesson.order == max(others)
    assert story.lesson.intro is not None
    assert 2 <= len(story.exercises) <= 3
    keys = {i: k for f in content.answers for i, k in f.keys.items()}
    for exercise in story.exercises:
        assert isinstance(exercise, StoryExercise)
        assert 3 <= len(exercise.scenes) <= 6
        assert exercise.scenes[0].illustration is not None, "a story opens with a picture"
        key = keys[exercise.id]
        assert isinstance(key, StoryAnswerKey)
        assert all(1 <= len(outcome.scenes) <= 3 for outcome in key.outcomes)


def test_validate_command_fails_loudly(tmp_path: Path, capsys: pytest.CaptureFixture) -> None:
    with pytest.raises(SystemExit, match="content validation failed: 1 problem"):
        main(["validate", str(tmp_path)])

    assert "directory not found" in capsys.readouterr().err


def test_seed_refuses_to_run_without_the_emulator(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)

    with pytest.raises(SystemExit, match="FIRESTORE_EMULATOR_HOST is not set"):
        main(["seed", str(CONTENT_DIR)])


@pytest.mark.parametrize(
    ("env", "message"),
    [
        ({"FIRESTORE_EMULATOR_HOST": "firebase:8080"}, "FIRESTORE_EMULATOR_HOST is set"),
        ({"FIREBASE_PROJECT_ID": "demo-ailearn"}, "emulator-only demo project"),
        ({"FIREBASE_PROJECT_ID": "ailearn-prod"}, "set CONFIRM_PROJECT=ailearn-prod"),
        (
            {"FIREBASE_PROJECT_ID": "ailearn-prod", "CONFIRM_PROJECT": "other-project"},
            "set CONFIRM_PROJECT=ailearn-prod",
        ),
    ],
)
def test_seed_production_refuses_without_explicit_confirmation(
    monkeypatch: pytest.MonkeyPatch, env: dict[str, str], message: str
) -> None:
    for name in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_PROJECT_ID", "CONFIRM_PROJECT"):
        monkeypatch.delenv(name, raising=False)
    for name, value in env.items():
        monkeypatch.setenv(name, value)

    with pytest.raises(SystemExit, match=message):
        main(["seed-production", str(CONTENT_DIR)])


def test_seed_production_writes_with_application_default_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    written: list[str] = []

    class FakeStore:
        def list_ids(self, collection: str) -> set[str]:
            return set()

        def apply(self, writes) -> None:
            written.extend(f"{w.collection}/{w.doc_id}" for w in writes)

    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "")
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "ailearn-prod")
    monkeypatch.setenv("CONFIRM_PROJECT", "ailearn-prod")
    connected: list[str] = []
    monkeypatch.setattr(
        "content_tools.__main__.connect_production",
        lambda project_id: connected.append(project_id) or FakeStore(),
    )

    main(["seed-production", str(CONTENT_DIR)])

    assert connected == ["ailearn-prod"]
    assert "units/u1" in written
    assert any(path.startswith("answerKeys/") for path in written)
