"""Story exercises: cross checks, scene pictures (`illustrate`), scene voices and seeding."""

from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
from app.ai import AiBlocked
from app.ai.image import GeneratedImage, ImageRateLimited
from app.ai.speech import mascot_voices
from app.mascot import DEFAULT_VOICE
from app.speech_cache import audio_path

from content_tools import __main__ as cli
from content_tools.audio_lines import (
    LINES_AUDIO_PREFIX,
    AudioLine,
    VoiceLine,
    read_audio_lines,
    unique_lines,
    write_audio_lines,
)
from content_tools.illustrations import (
    ILLUSTRATIONS_FILE,
    STYLE_PROMPT,
    CachedIllustrator,
    SceneImage,
    illustrate,
    image_path,
    read_scene_images,
    unique_prompts,
    write_scene_images,
)
from content_tools.scene_voices import SCENE_VOICES, voices_for
from content_tools.validate import validate_content
from tests.conftest import Tree, valid_tree

MakeContent = Callable[[Tree], Path]
LESSON_FILE = "units/u9/u9-l2.yaml"
ANSWERS_FILE = "units/u9/u9-l2.answers.yaml"
STORY_ID = "u9-l2-q1"
ROOM = "Yui at her desk in her room"
LIBRARY = "Yui reading a picture book about fireflies in a library"


def story_tree() -> Tree:
    tree = valid_tree()
    tree[LESSON_FILE] = {
        "lesson": {
            "id": "u9-l2",
            "unitId": "u9",
            "order": 2,
            "title": "紙しばい",
            "exerciseIds": [STORY_ID],
        },
        "exercises": [
            {
                "id": STORY_ID,
                "lessonId": "u9-l2",
                "type": "story",
                "title": "自由研究",
                "question": "ユイはどうする？",
                "scenes": [
                    {
                        "speaker": "narrator",
                        "text": "ユイは自由研究をしています。",
                        "illustration": {"prompt": ROOM},
                    },
                    {"speaker": "ai", "text": "ホタルは電気で光ります。"},
                    {
                        "speaker": "student",
                        "text": "このまま書こうかな。",
                        "illustration": {"prompt": ROOM},  # the same picture is drawn once
                    },
                ],
                "options": [
                    {"id": "copy", "text": "そのまま書く"},
                    {"id": "check", "text": "図鑑で確かめる"},
                ],
            }
        ],
    }
    tree[ANSWERS_FILE] = {
        STORY_ID: {
            "type": "story",
            "bestOptionId": "check",
            "outcomes": [
                {
                    "optionId": "copy",
                    "scenes": [{"speaker": "teacher", "text": "どこで調べたの？"}],
                },
                {
                    "optionId": "check",
                    "scenes": [
                        {
                            "speaker": "student",
                            "text": "化学反応だった！",
                            "illustration": {"prompt": LIBRARY},
                        },
                        # The narrator says the same text as the AI: a different voice.
                        {"speaker": "narrator", "text": "ホタルは電気で光ります。"},
                    ],
                },
            ],
            "explanation": "AI 以外の情報源で確かめよう。",
        }
    }
    return tree


def _messages(make_content: MakeContent, tree: Tree) -> list[str]:
    return [problem.message for problem in validate_content(make_content(tree)).problems]


# ---- validation ---------------------------------------------------------------------------


def test_story_tree_is_valid(make_content: MakeContent) -> None:
    assert _messages(make_content, story_tree()) == []


def test_outcomes_must_cover_exactly_the_options(make_content: MakeContent) -> None:
    tree = story_tree()
    tree[ANSWERS_FILE][STORY_ID]["outcomes"][0]["optionId"] = "guess"
    tree[ANSWERS_FILE][STORY_ID]["outcomes"][1]["optionId"] = "copy"
    tree[ANSWERS_FILE][STORY_ID]["bestOptionId"] = "copy"

    [message] = _messages(make_content, tree)

    assert message == (
        f"{STORY_ID}: outcomes ['copy', 'guess'] must have exactly one entry per option "
        "['check', 'copy']"
    )


def test_best_option_must_be_an_option(make_content: MakeContent) -> None:
    tree = story_tree()
    exercise = tree[LESSON_FILE]["exercises"][0]
    exercise["options"][1]["id"] = "ask"

    messages = _messages(make_content, tree)

    assert f"{STORY_ID}: bestOptionId 'check' is not one of ['copy', 'ask']" in messages
    assert len(messages) == 2  # the outcomes no longer match the options either


@pytest.mark.parametrize(
    ("file", "edit", "expected"),
    [
        (
            LESSON_FILE,
            lambda t: t[LESSON_FILE]["exercises"][0]["scenes"][0]["illustration"].update(
                imagePath="images/scenes/x.jpg"
            ),
            f"exercise {STORY_ID} scenes[0]: illustration.imagePath is filled in from "
            "images/scenes.yaml by `make illustrate`; remove it",
        ),
        (
            ANSWERS_FILE,
            lambda t: t[ANSWERS_FILE][STORY_ID]["outcomes"][1]["scenes"][0]["illustration"].update(
                imagePath="images/scenes/x.jpg"
            ),
            f"{STORY_ID} outcome check scenes[0]: illustration.imagePath is filled in from "
            "images/scenes.yaml by `make illustrate`; remove it",
        ),
        (
            LESSON_FILE,
            lambda t: t[LESSON_FILE]["exercises"][0]["scenes"][1].update(
                audioPath="audio/lines/x.mp3"
            ),
            f"exercise {STORY_ID} scenes[1]: audioPath is filled in from audio/lines.yaml by "
            "`make speak`; remove it",
        ),
        (
            ANSWERS_FILE,
            lambda t: t[ANSWERS_FILE][STORY_ID]["outcomes"][0]["scenes"][0].update(
                audioPath="audio/lines/x.mp3"
            ),
            f"{STORY_ID} outcome copy scenes[0]: audioPath is filled in from audio/lines.yaml "
            "by `make speak`; remove it",
        ),
    ],
    ids=["exercise image", "outcome image", "exercise audio", "outcome audio"],
)
def test_generated_paths_written_by_hand_are_rejected(
    make_content: MakeContent, file: str, edit: Callable[[Tree], Any], expected: str
) -> None:
    tree = story_tree()
    edit(tree)

    report = validate_content(make_content(tree))

    [problem] = report.problems
    assert problem.path.name == Path(file).name
    assert problem.message == expected


@pytest.mark.parametrize(
    "text",
    [
        "images:\n  - prompt: x\n    imagePath: audio/lines/x.jpg\n",
        "images:\n  - prompt: x\n    imagePath: images/scenes/" + "a" * 64 + ".jpg\n"
        "  - prompt: x\n    imagePath: images/scenes/" + "b" * 64 + ".jpg\n",
        "images: [\n",
    ],
    ids=["outside images/scenes", "duplicate prompt", "broken yaml"],
)
def test_broken_scene_images_file_fails_validation(make_content: MakeContent, text: str) -> None:
    root = make_content(story_tree())
    (root / ILLUSTRATIONS_FILE).parent.mkdir()
    (root / ILLUSTRATIONS_FILE).write_text(text, encoding="utf-8")

    [problem] = validate_content(root).problems

    assert problem.path == root / ILLUSTRATIONS_FILE


# ---- what gets generated ------------------------------------------------------------------


def test_every_scene_line_is_spoken_once_per_speaker(make_content: MakeContent) -> None:
    report = validate_content(make_content(story_tree()))

    assert unique_lines(report.content) == [
        VoiceLine("mascot", "はじめよう"),
        VoiceLine("narrator", "ユイは自由研究をしています。"),
        VoiceLine("ai", "ホタルは電気で光ります。"),
        VoiceLine("student", "このまま書こうかな。"),
        VoiceLine("teacher", "どこで調べたの？"),
        VoiceLine("student", "化学反応だった！"),
        VoiceLine("narrator", "ホタルは電気で光ります。"),
    ]


def test_every_prompt_is_drawn_once(make_content: MakeContent) -> None:
    report = validate_content(make_content(story_tree()))

    assert unique_prompts(report.content) == [ROOM, LIBRARY]


def test_each_speaker_has_its_own_voice_and_the_mascot_keeps_the_api_voice() -> None:
    client: Any = object()
    ids = {
        speaker: [v.voice_id for v in voices_for(client, "tts-model", speaker, DEFAULT_VOICE)]
        for speaker in [*SCENE_VOICES, "mascot"]
    }

    assert ids["mascot"] == [v.voice_id for v in mascot_voices(client, "tts-model", DEFAULT_VOICE)]
    assert len({voice_ids[0] for voice_ids in ids.values()}) == len(ids)
    assert ids["student"][1] == "chirp3-hd/ja-JP-Chirp3-HD-Zephyr"


# ---- seeding ------------------------------------------------------------------------------


def _image(prompt: str) -> str:
    return image_path("image-model", prompt)


def _audio(line: VoiceLine) -> str:
    return audio_path(LINES_AUDIO_PREFIX, f"voice-of-{line.speaker}", line.text)


def test_seed_fills_generated_paths_in_exercises_and_answer_keys(
    make_content: MakeContent, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_content(story_tree())
    write_scene_images(root, [SceneImage(prompt=p, image_path=_image(p)) for p in [ROOM, LIBRARY]])
    spoken = [VoiceLine("ai", "ホタルは電気で光ります。"), VoiceLine("teacher", "どこで調べたの？")]
    write_audio_lines(
        root,
        [AudioLine(speaker=v.speaker, text=v.text, audio_path=_audio(v)) for v in spoken],
    )
    seeded: list[dict[str, Any]] = []
    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", "localhost:8080")
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-test")
    monkeypatch.setattr(cli, "wait_for_emulator", lambda host, seconds: None)
    monkeypatch.setattr(cli, "connect_emulator", lambda project_id: object())
    monkeypatch.setattr(
        cli, "sync", lambda store, documents: seeded.append(documents) or _summary(documents)
    )

    cli.main(["seed", str(root)])

    [documents] = seeded
    scenes = documents["exercises"][STORY_ID]["scenes"]
    assert scenes[0]["illustration"] == {"prompt": ROOM, "imagePath": _image(ROOM)}
    assert scenes[2]["illustration"]["imagePath"] == _image(ROOM)
    assert scenes[1]["audioPath"] == _audio(spoken[0])
    # No audio yet: text only.
    assert "audioPath" not in scenes[0]
    outcomes = documents["answerKeys"][STORY_ID]["outcomes"]
    assert outcomes[0]["scenes"][0]["audioPath"] == _audio(spoken[1])
    assert outcomes[1]["scenes"][0]["illustration"]["imagePath"] == _image(LIBRARY)
    # Same text, other speaker: the AI's audio is not reused for the narrator.
    assert "audioPath" not in outcomes[1]["scenes"][1]


def _summary(documents: dict[str, dict[str, Any]]) -> Any:
    from content_tools.seed import SyncSummary

    return SyncSummary(
        written={c: len(d) for c, d in documents.items()},
        deleted={c: 0 for c in documents},
    )


# ---- illustrate ---------------------------------------------------------------------------


class FakeStore:
    def __init__(self, existing: set[str] = frozenset()) -> None:  # type: ignore[assignment]
        self.files: dict[str, tuple[bytes, str]] = {
            path: (b"old", "image/jpeg") for path in existing
        }

    def exists(self, path: str) -> bool:
        return path in self.files

    def put(self, path: str, data: bytes, content_type: str) -> None:
        self.files[path] = (data, content_type)


class FakeImages:
    model = "image-model"

    def __init__(self, blocked: frozenset[str] = frozenset(), mime: str = "image/jpeg") -> None:
        self.blocked = blocked
        self.mime = mime
        self.prompts: list[str] = []

    def generate(self, prompt: str) -> GeneratedImage:
        self.prompts.append(prompt)
        if any(word in prompt for word in self.blocked):
            raise AiBlocked("output blocked")
        return GeneratedImage(data=f"jpeg:{len(self.prompts)}".encode(), mime_type=self.mime)


def test_illustrator_draws_new_prompts_in_the_shared_style_and_reuses_stored_ones() -> None:
    store = FakeStore(existing=frozenset({_image(ROOM)}))
    images = FakeImages()
    illustrator = CachedIllustrator(store, images, max_new=5)

    drawn, missing = illustrate(illustrator, [ROOM, LIBRARY])

    assert missing == []
    assert drawn == [
        SceneImage(prompt=ROOM, image_path=_image(ROOM)),
        SceneImage(prompt=LIBRARY, image_path=_image(LIBRARY)),
    ]
    assert images.prompts == [STYLE_PROMPT + LIBRARY]
    assert store.files[_image(LIBRARY)] == (b"jpeg:1", "image/jpeg")
    assert illustrator.generated == 1
    assert "no text" in STYLE_PROMPT.lower()


def test_illustrator_stops_at_the_limit_and_reports_blocked_pictures() -> None:
    images = FakeImages(blocked=frozenset({"library"}))
    illustrator = CachedIllustrator(FakeStore(), images, max_new=2)

    drawn, missing = illustrate(illustrator, [LIBRARY, ROOM, "Sota in the classroom"])

    assert [d.prompt for d in drawn] == [ROOM]
    assert [(m.prompt, m.reason.split(":")[0]) for m in missing] == [
        (LIBRARY, "AiBlocked"),
        ("Sota in the classroom", "BudgetExhausted"),
    ]
    assert illustrator.requested == 2  # the blocked request counts, it may be billed
    assert illustrator.generated == 1


def test_illustrator_waits_out_the_quota_without_counting_it() -> None:
    class Limited(FakeImages):
        def __init__(self, limited: int) -> None:
            super().__init__()
            self.limited = limited

        def generate(self, prompt: str) -> GeneratedImage:
            if self.limited:
                self.limited -= 1
                raise ImageRateLimited("quota")
            return super().generate(prompt)

    waits: list[float] = []
    illustrator = CachedIllustrator(FakeStore(), Limited(2), 1, waits=(5, 7), sleep=waits.append)

    drawn, missing = illustrate(illustrator, [ROOM])

    assert [d.prompt for d in drawn] == [ROOM] and missing == []
    assert waits == [5, 7]
    assert (illustrator.requested, illustrator.generated) == (1, 1)

    gave_up = CachedIllustrator(FakeStore(), Limited(3), 1, waits=(5, 7), sleep=waits.append)
    _, missing = illustrate(gave_up, [ROOM])
    assert missing[0].reason.startswith("ImageRateLimited")
    assert gave_up.requested == 0


def test_picture_in_another_format_is_not_stored() -> None:
    store = FakeStore()
    drawn, missing = illustrate(CachedIllustrator(store, FakeImages(mime="image/png"), 1), [ROOM])

    assert drawn == [] and store.files == {}
    assert "image/png" in missing[0].reason


def test_image_path_depends_on_model_and_prompt() -> None:
    assert image_path("a", ROOM) != image_path("b", ROOM)
    assert image_path("a", ROOM) != image_path("a", LIBRARY)
    assert image_path("a", ROOM).startswith("images/scenes/")


def test_scene_images_file_round_trips(tmp_path: Path) -> None:
    images = [SceneImage(prompt=ROOM, image_path=_image(ROOM))]

    path = write_scene_images(tmp_path, images)
    loaded, problems = read_scene_images(tmp_path)

    assert path.read_text(encoding="utf-8").startswith("# `make illustrate`")
    assert (loaded.images, problems) == (images, [])


def test_illustrate_command_writes_the_mapping_and_fails_for_missing_pictures(
    make_content: MakeContent,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    root = make_content(story_tree())
    env = {
        "IMAGE_MODEL": "image-model",
        "VERTEX_PROJECT": "p",
        "STORAGE_BUCKET": "b",
        "FIREBASE_PROJECT_ID": "p",
    }
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    images = FakeImages()
    store = FakeStore()
    monkeypatch.setattr(cli.firebase_admin, "initialize_app", lambda **kwargs: object())
    monkeypatch.setattr(cli, "firebase_bucket", lambda app, name: object())
    monkeypatch.setattr(cli, "BucketImageStore", lambda bucket: store)
    monkeypatch.setattr(cli, "vertex_models", lambda project, location, timeout: object())
    monkeypatch.setattr(cli, "GeminiImageGenerator", lambda models, model: images)

    with pytest.raises(SystemExit, match="1 scene"):
        cli.main(["illustrate", str(root), "--max-new", "1"])

    loaded, _ = read_scene_images(root)
    assert loaded.paths_by_prompt() == {ROOM: _image(ROOM)}
    output = capsys.readouterr()
    assert "(1 newly generated, 1 billable image request(s), limit 1)" in output.out
    assert "BudgetExhausted" in output.err


def test_illustrate_command_needs_the_image_model(
    make_content: MakeContent, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("IMAGE_MODEL", raising=False)

    with pytest.raises(SystemExit, match="IMAGE_MODEL is not set"):
        cli.main(["illustrate", str(make_content(story_tree()))])


def test_speak_command_uses_the_voice_of_each_speaker(
    make_content: MakeContent, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    root = make_content(story_tree())
    for name, value in [("TTS_MODEL", "m"), ("STORAGE_BUCKET", "b"), ("FIREBASE_PROJECT_ID", "p")]:
        monkeypatch.setenv(name, value)
    asked: list[tuple[str, str]] = []

    class FakeSpeech:
        def __init__(self, store: Any, voices: list[Any], prefix: str) -> None:
            self.voice = voices[0].voice_id
            self.store = store

        def audio_path_for(self, text: str) -> str:
            asked.append((self.voice, text))
            path = audio_path(LINES_AUDIO_PREFIX, self.voice, text)
            self.store.put(path, b"mp3", "audio/mpeg")
            return path

    monkeypatch.setattr(cli.firebase_admin, "initialize_app", lambda **kwargs: object())
    monkeypatch.setattr(cli, "firebase_bucket", lambda app, name: object())
    monkeypatch.setattr(cli, "BucketAudioStore", lambda bucket: FakeStore())
    monkeypatch.setattr(cli, "tts_client", lambda: object())
    monkeypatch.setattr(cli, "CachedSpeech", FakeSpeech)

    cli.main(["speak", str(root)])

    audio, _ = read_audio_lines(root)
    assert len(audio.lines) == 7
    voices = {voice.split("/")[2] for voice, _ in asked}
    assert voices == {DEFAULT_VOICE, *(SCENE_VOICES[s].name for s in SCENE_VOICES if s != "friend")}
    assert "(7 newly synthesized)" in capsys.readouterr().out
