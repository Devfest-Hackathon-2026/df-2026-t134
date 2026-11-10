"""Export the shared contracts as JSON files for the app, tools and reviewers.

Usage: python -m scripts.export_schemas <docs_dir> <content_schema_dir>
"""

import json
import sys
from pathlib import Path
from typing import Literal

from pydantic import TypeAdapter

from app.ai import UnconfiguredGenerator
from app.auth import CurrentUser
from app.clock import system_clock
from app.config import Settings
from app.main import create_app
from app.repo.memory import InMemoryLearningRepo
from app.schemas import content, firestore
from app.services.feedback_audio import UnconfiguredSpeech

Mode = Literal["validation", "serialization"]


class _NoTokenVerifier:
    """The OpenAPI export never serves requests, so it needs no Firebase connection."""

    def verify_id_token(self, id_token: str) -> CurrentUser | None:
        return None

    def verify_app_check_token(self, app_check_token: str) -> bool:
        return False


def _schema(target: object, title: str, mode: Mode) -> dict[str, object]:
    schema = TypeAdapter(target).json_schema(mode=mode, by_alias=True)
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "title": title, **schema}


def _write(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def main(docs_dir: Path, content_schema_dir: Path) -> None:
    app = create_app(
        Settings(app_env="test"),
        _NoTokenVerifier(),
        InMemoryLearningRepo(),
        system_clock,
        UnconfiguredGenerator(),
        UnconfiguredSpeech(),
    )
    openapi = app.openapi()
    _write(docs_dir / "openapi.json", openapi)

    # Content is authored by hand, so describe what is accepted (validation mode).
    for name, target in {
        "unit": content.Unit,
        "lesson": content.Lesson,
        "exercise": content.Exercise,
        "answer_key": content.AnswerKey,
    }.items():
        _write(content_schema_dir / f"{name}.schema.json", _schema(target, name, "validation"))

    # Firestore documents are written by the server and read by the app (serialization mode).
    for name, target in {
        "user_profile": firestore.UserProfile,
        "progress": firestore.Progress,
        "attempt": firestore.Attempt,
        "live_check_session": firestore.LiveCheckSession,
    }.items():
        path = docs_dir / "schemas" / "firestore" / f"{name}.schema.json"
        _write(path, _schema(target, name, "serialization"))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
