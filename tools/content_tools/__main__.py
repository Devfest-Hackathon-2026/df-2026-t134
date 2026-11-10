"""Command line:
    python -m content_tools validate|seed|seed-production|speak <content dir>
    python -m content_tools illustrate <content dir> [--max-new N]
    python -m content_tools draft-hallucination <drafts dir> --lesson <id> --topic <topic> ...

Environment is read here only and passed on as arguments:
- FIREBASE_PROJECT_ID: project to seed (compose sets demo-ailearn), and of the bucket for `speak`
- FIRESTORE_EMULATOR_HOST: required by `seed`, must be unset or empty for `seed-production`
- CONFIRM_PROJECT: `seed-production` only runs when it equals FIREBASE_PROJECT_ID, so the
  real project is never written by accident; it uses Application Default Credentials
- TTS_MODEL, TTS_VOICE (optional), STORAGE_BUCKET: required by `speak`, which calls
  Cloud Text-to-Speech and Cloud Storage with Application Default Credentials
- IMAGE_MODEL, VERTEX_PROJECT, VERTEX_LOCATION (default global), STORAGE_BUCKET: required by
  `illustrate`, which calls the Gemini image model and Cloud Storage with ADC
- GEMINI_MODEL, VERTEX_PROJECT, VERTEX_LOCATION (default global): required by
  `draft-hallucination`, which calls Gemini with Application Default Credentials
"""

import argparse
import datetime as dt
import os
import sys
from pathlib import Path

import firebase_admin
from app.ai import AiBlocked, AiUnavailable
from app.ai.gemini import GeminiGroundedWriter, GeminiJsonGenerator, vertex_models
from app.ai.image import GeminiImageGenerator
from app.ai.speech import tts_client
from app.mascot import DEFAULT_VOICE
from app.schemas.content import HallucinationErrorType, Speaker
from app.speech_cache import CachedSpeech
from app.storage import AudioStore, BucketAudioStore, BucketImageStore, firebase_bucket

from content_tools.audio_lines import (
    LINES_AUDIO_PREFIX,
    read_audio_lines,
    speak,
    unique_lines,
    with_audio,
    write_audio_lines,
)
from content_tools.drafts import next_exercise_id, write_draft
from content_tools.firestore_store import connect_emulator, connect_production, wait_for_emulator
from content_tools.hallucination import ERROR_TYPE_GUIDES, DraftRejected, draft_exercise
from content_tools.illustrations import (
    DEFAULT_MAX_NEW_IMAGES,
    SCENES_IMAGE_PREFIX,
    CachedIllustrator,
    illustrate,
    read_scene_images,
    unique_prompts,
    with_images,
    write_scene_images,
)
from content_tools.loader import Content
from content_tools.scene_voices import voices_for
from content_tools.seed import build_documents, sync
from content_tools.validate import Report, validate_content

EMULATOR_WAIT_SECONDS = 60
# Drafting is not interactive and searches the web first, so it may take a while.
GENERATION_TIMEOUT_SECONDS = 120
IMAGE_TIMEOUT_SECONDS = 120
DEFAULT_ERROR_TYPES: list[HallucinationErrorType] = ["number", "causality"]


def _validated(content_dir: Path) -> Report:
    report = validate_content(content_dir)
    if not report.ok:
        for problem in report.problems:
            print(f"ERROR {problem}", file=sys.stderr)
        sys.exit(f"content validation failed: {len(report.problems)} problem(s)")
    content = report.content
    exercises = sum(len(f.exercises) for f in content.lessons)
    print(
        f"content OK: {len(content.units)} unit(s), {len(content.lessons)} lesson(s), "
        f"{exercises} exercise(s)"
    )
    return report


def _required_env(name: str, reason: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"{name} is not set: {reason}")
    return value


def run_validate(args: argparse.Namespace) -> None:
    _validated(args.content_dir)


def _with_media(content: Content, content_dir: Path) -> Content:
    """Content with the generated audio and picture paths filled in (both files were already
    checked by _validated)."""
    audio, _ = read_audio_lines(content_dir)
    images, _ = read_scene_images(content_dir)
    return with_images(with_audio(content, audio.paths_by_line()), images.paths_by_prompt())


def run_seed(args: argparse.Namespace) -> None:
    emulator_host = _required_env(
        "FIRESTORE_EMULATOR_HOST",
        "seed only writes to the Firestore emulator (production seeding is not supported yet). "
        "Run it with `make seed`.",
    )
    project_id = _required_env("FIREBASE_PROJECT_ID", "the project to seed is unknown")
    content = _validated(args.content_dir).content
    documents = build_documents(_with_media(content, args.content_dir))

    print(f"waiting for the Firestore emulator at {emulator_host} ...")
    wait_for_emulator(emulator_host, EMULATOR_WAIT_SECONDS)
    summary = sync(connect_emulator(project_id), documents)
    for collection, written in summary.written.items():
        print(f"{collection}: wrote {written}, deleted {summary.deleted[collection]}")
    print(f"seeded project {project_id} on {emulator_host}")


def run_seed_production(args: argparse.Namespace) -> None:
    if os.environ.get("FIRESTORE_EMULATOR_HOST", "").strip():
        sys.exit("FIRESTORE_EMULATOR_HOST is set: use `seed` for the emulator")
    # An empty value would still make the client library look for an emulator.
    os.environ.pop("FIRESTORE_EMULATOR_HOST", None)
    project_id = _required_env("FIREBASE_PROJECT_ID", "the project to seed is unknown")
    if project_id.startswith("demo-"):
        sys.exit(f"{project_id} is an emulator-only demo project: use `seed`")
    confirmed = os.environ.get("CONFIRM_PROJECT", "").strip()
    if confirmed != project_id:
        sys.exit(
            f"refusing to write production Firestore of {project_id}: "
            f"set CONFIRM_PROJECT={project_id} to confirm"
        )
    content = _validated(args.content_dir).content
    documents = build_documents(_with_media(content, args.content_dir))
    summary = sync(connect_production(project_id), documents)
    for collection, written in summary.written.items():
        print(f"{collection}: wrote {written}, deleted {summary.deleted[collection]}")
    print(f"seeded production project {project_id}")


def run_speak(args: argparse.Namespace) -> None:
    model = _required_env("TTS_MODEL", "the Gemini-TTS model ID of the mascot's voice")
    bucket_name = _required_env("STORAGE_BUCKET", "the bucket the app reads audio from")
    project_id = _required_env("FIREBASE_PROJECT_ID", "the project that owns the bucket")
    voice = os.environ.get("TTS_VOICE", "").strip() or DEFAULT_VOICE
    lines = unique_lines(_validated(args.content_dir).content)

    firebase_app = firebase_admin.initialize_app(options={"projectId": project_id}, name="speak")
    store = CountingStore(BucketAudioStore(firebase_bucket(firebase_app, bucket_name)))
    client = tts_client()
    speeches: dict[Speaker, CachedSpeech] = {}

    def speech_of(speaker: Speaker) -> CachedSpeech:
        if speaker not in speeches:
            voices = voices_for(client, model, speaker, voice)
            speeches[speaker] = CachedSpeech(store, voices, LINES_AUDIO_PREFIX)
        return speeches[speaker]

    spoken, failed = speak(speech_of, lines)
    path = write_audio_lines(args.content_dir, spoken)
    print(
        f"wrote {path}: {len(spoken)} line(s) in gs://{bucket_name}/{LINES_AUDIO_PREFIX} "
        f"({store.written} newly synthesized)"
    )
    if failed:
        for line in failed:
            print(f"NO AUDIO {line.speaker}: {line.text!r}", file=sys.stderr)
        sys.exit(f"no voice could speak {len(failed)} line(s). Run `make speak` again.")


class CountingStore:
    """A store that counts what is written (new media, i.e. what was paid for)."""

    def __init__(self, store: AudioStore) -> None:
        self._store = store
        self.written = 0

    def exists(self, path: str) -> bool:
        return self._store.exists(path)

    def put(self, path: str, data: bytes, content_type: str) -> None:
        self._store.put(path, data, content_type)
        self.written += 1


def run_illustrate(args: argparse.Namespace) -> None:
    model = _required_env("IMAGE_MODEL", "the Gemini image model ID that draws the scenes")
    project = _required_env("VERTEX_PROJECT", "the Google Cloud project that runs Vertex AI")
    bucket_name = _required_env("STORAGE_BUCKET", "the bucket the app reads pictures from")
    project_id = _required_env("FIREBASE_PROJECT_ID", "the project that owns the bucket")
    location = os.environ.get("VERTEX_LOCATION", "").strip() or "global"
    prompts = unique_prompts(_validated(args.content_dir).content)

    firebase_app = firebase_admin.initialize_app(
        options={"projectId": project_id}, name="illustrate"
    )
    store = BucketImageStore(firebase_bucket(firebase_app, bucket_name))
    generator = GeminiImageGenerator(vertex_models(project, location, IMAGE_TIMEOUT_SECONDS), model)
    illustrator = CachedIllustrator(store, generator, args.max_new)
    drawn, missing = illustrate(illustrator, prompts)
    path = write_scene_images(args.content_dir, drawn)
    print(
        f"wrote {path}: {len(drawn)} picture(s) in gs://{bucket_name}/{SCENES_IMAGE_PREFIX} "
        f"({illustrator.generated} newly generated, {illustrator.requested} billable image "
        f"request(s), limit {args.max_new})"
    )
    if missing:
        for item in missing:
            print(f"NO PICTURE {item.prompt[:60]!r}: {item.reason}", file=sys.stderr)
        sys.exit(f"{len(missing)} scene(s) have no picture yet. Run `make illustrate` again.")


def run_draft_hallucination(args: argparse.Namespace) -> None:
    model = _required_env("GEMINI_MODEL", "the Gemini model ID that writes the drafts")
    project = _required_env("VERTEX_PROJECT", "the Google Cloud project that runs Vertex AI")
    location = os.environ.get("VERTEX_LOCATION", "").strip() or "global"
    error_types: list[HallucinationErrorType] = args.error_types or DEFAULT_ERROR_TYPES
    models = vertex_models(project, location, GENERATION_TIMEOUT_SECONDS)
    writer, generator = GeminiGroundedWriter(models, model), GeminiJsonGenerator(models, model)

    failed: list[str] = []
    for topic in args.topics:
        exercise_id = next_exercise_id(args.drafts_dir, args.lesson)
        try:
            draft = draft_exercise(writer, generator, exercise_id, args.lesson, topic, error_types)
        except (DraftRejected, AiUnavailable, AiBlocked) as error:
            # One bad answer from the model should not stop the other topics.
            print(f"SKIP {topic}: {type(error).__name__}: {error}", file=sys.stderr)
            failed.append(topic)
            continue
        generated_at = dt.datetime.now(dt.UTC).replace(microsecond=0)
        path = write_draft(args.drafts_dir, draft, model, generated_at)
        print(f"wrote {path} ({topic}, {len(draft.sources)} source(s))")
    if failed:
        sys.exit(f"no draft for {len(failed)} topic(s): {', '.join(failed)}. Run them again.")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="python -m content_tools", description=__doc__)
    commands = parser.add_subparsers(required=True, metavar="command")
    for name, handler, help_text in [
        ("validate", run_validate, "check every content file and cross reference"),
        ("seed", run_seed, "validate, then mirror the content into the Firestore emulator"),
        (
            "seed-production",
            run_seed_production,
            "validate, then mirror the content into production Firestore (CONFIRM_PROJECT)",
        ),
        (
            "speak",
            run_speak,
            "pre-generate the audio of every intro and story scene into Cloud Storage",
        ),
    ]:
        command = commands.add_parser(name, help=help_text)
        command.add_argument("content_dir", type=Path, help="the content/ directory")
        command.set_defaults(handler=handler)
    illustration = commands.add_parser(
        "illustrate", help="draw every story scene picture with the image model into Cloud Storage"
    )
    illustration.add_argument("content_dir", type=Path, help="the content/ directory")
    illustration.add_argument(
        "--max-new",
        type=int,
        default=DEFAULT_MAX_NEW_IMAGES,
        help=f"most new pictures to generate in this run (default {DEFAULT_MAX_NEW_IMAGES})",
    )
    illustration.set_defaults(handler=run_illustrate)
    draft = commands.add_parser(
        "draft-hallucination",
        help="draft hallucination exercises with Gemini for a person to review",
    )
    draft.add_argument("drafts_dir", type=Path, help="where to write the drafts")
    draft.add_argument("--lesson", required=True, help="lesson the drafts are meant for")
    draft.add_argument(
        "--topic", dest="topics", action="append", required=True, help="repeat for each topic"
    )
    draft.add_argument(
        "--error-type",
        dest="error_types",
        action="append",
        choices=list(ERROR_TYPE_GUIDES),
        help=f"error to put in (repeat for 2 or 3; default: {' '.join(DEFAULT_ERROR_TYPES)})",
    )
    draft.set_defaults(handler=run_draft_hallucination)
    args = parser.parse_args(argv)
    args.handler(args)


if __name__ == "__main__":
    main()
