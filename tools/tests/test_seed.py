from collections.abc import Callable, Sequence
from pathlib import Path

from content_tools.seed import (
    COLLECTIONS,
    DeleteDocument,
    SetDocument,
    Write,
    build_documents,
    plan_writes,
    sync,
)
from content_tools.validate import validate_content
from tests.conftest import Tree, valid_tree


class FakeStore:
    """In-memory DocumentStore: {collection: {doc id: data}}."""

    def __init__(self, existing: dict[str, dict[str, dict]] | None = None) -> None:
        self.docs = {c: dict((existing or {}).get(c, {})) for c in COLLECTIONS}
        self.applied: list[Write] = []

    def list_ids(self, collection: str) -> set[str]:
        return set(self.docs[collection])

    def apply(self, writes: Sequence[Write]) -> None:
        self.applied += writes
        for write in writes:
            match write:
                case SetDocument():
                    self.docs[write.collection][write.doc_id] = write.data
                case DeleteDocument():
                    del self.docs[write.collection][write.doc_id]


def documents(make_content: Callable[[Tree], Path]) -> dict:
    report = validate_content(make_content(valid_tree()))
    assert report.ok
    return build_documents(report.content)


def test_documents_use_model_ids_and_camel_case_json(make_content) -> None:
    docs = documents(make_content)

    assert docs["units"] == {
        "u9": {
            "id": "u9",
            "order": 1,
            "title": "テスト",
            "description": "テスト用のユニット",
            "level": 1,
        }
    }
    # The optional intro.audioPath (None) is left out.
    assert docs["lessons"]["u9-l1"] == {
        "id": "u9-l1",
        "unitId": "u9",
        "order": 1,
        "title": "レッスン",
        "exerciseIds": ["u9-l1-q1", "u9-l1-q2", "u9-l1-q3", "u9-l1-q4", "u9-l1-q5"],
        "intro": {"text": "はじめよう"},
    }
    assert (
        sorted(docs["exercises"])
        == sorted(docs["answerKeys"])
        == [f"u9-l1-q{n}" for n in range(1, 6)]
    )
    assert docs["exercises"]["u9-l1-q4"]["errorCount"] == 1
    # Defaults are written too, so readers never have to know them.
    assert docs["exercises"]["u9-l1-q5"]["maxLength"] == 400


def test_answer_keys_are_stored_only_in_answer_keys(make_content) -> None:
    docs = documents(make_content)

    assert docs["answerKeys"]["u9-l1-q1"] == {
        "type": "choice",
        "correctOptionId": "a",
        "explanation": "予測",
    }
    assert docs["answerKeys"]["u9-l1-q3"]["correctOptions"] == {"p": "a", "q": "d"}
    for exercise in docs["exercises"].values():
        assert not {"correctOptionId", "correctOrder", "correctOptions", "errors"} & set(exercise)


def test_plan_sets_everything_and_deletes_stale_documents() -> None:
    desired = {c: {} for c in COLLECTIONS} | {"units": {"u1": {"id": "u1"}}}
    existing = {c: set() for c in COLLECTIONS} | {"units": {"u1", "u0"}, "answerKeys": {"x"}}

    writes = plan_writes(desired, existing)

    assert writes == [
        SetDocument("units", "u1", {"id": "u1"}),
        DeleteDocument("units", "u0"),
        DeleteDocument("answerKeys", "x"),
    ]


def test_sync_mirrors_content_and_is_idempotent(make_content) -> None:
    docs = documents(make_content)
    store = FakeStore({"lessons": {"old-lesson": {"id": "old-lesson"}}})

    first = sync(store, docs)
    second = sync(store, docs)

    assert store.docs == docs
    assert first.deleted["lessons"] == 1
    assert (
        first.written
        == second.written
        == {
            "units": 1,
            "lessons": 1,
            "exercises": 5,
            "answerKeys": 5,
        }
    )
    assert sum(second.deleted.values()) == 0
