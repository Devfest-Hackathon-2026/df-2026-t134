"""Turn validated content into Firestore documents and make the four content collections
mirror it (set every document, delete the ones that are no longer in content/).

Document id = model id; data = model_dump(mode="json", exclude_none=True) (camelCase, includes
`id`; answer keys have no `id` field and are stored under the exercise id).
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Protocol

from app.schemas.firestore import (
    ANSWER_KEYS_COLLECTION,
    EXERCISES_COLLECTION,
    LESSONS_COLLECTION,
    UNITS_COLLECTION,
)
from pydantic import BaseModel

from content_tools.loader import Content

# The collection names are defined once, next to the Firestore contracts.
COLLECTIONS = (UNITS_COLLECTION, LESSONS_COLLECTION, EXERCISES_COLLECTION, ANSWER_KEYS_COLLECTION)

type DocumentData = dict[str, object]
type Documents = dict[str, dict[str, DocumentData]]


@dataclass(frozen=True)
class SetDocument:
    collection: str
    doc_id: str
    data: DocumentData


@dataclass(frozen=True)
class DeleteDocument:
    collection: str
    doc_id: str


type Write = SetDocument | DeleteDocument


class DocumentStore(Protocol):
    """The only Firestore operations seeding needs (see firestore_store.py)."""

    def list_ids(self, collection: str) -> set[str]: ...

    def apply(self, writes: Sequence[Write]) -> None: ...


@dataclass(frozen=True)
class SyncSummary:
    written: Mapping[str, int]
    deleted: Mapping[str, int]


def _data(model: BaseModel) -> DocumentData:
    return model.model_dump(mode="json", exclude_none=True)


def build_documents(content: Content) -> Documents:
    """Content (already validated) -> {collection: {doc id: data}}."""
    return {
        UNITS_COLLECTION: {f.unit.id: _data(f.unit) for f in content.units},
        LESSONS_COLLECTION: {f.lesson.id: _data(f.lesson) for f in content.lessons},
        EXERCISES_COLLECTION: {e.id: _data(e) for f in content.lessons for e in f.exercises},
        ANSWER_KEYS_COLLECTION: {
            exercise_id: _data(key) for f in content.answers for exercise_id, key in f.keys.items()
        },
    }


def plan_writes(desired: Documents, existing: Mapping[str, set[str]]) -> list[Write]:
    """Sets for every desired document, then deletes for existing ones that are not desired."""
    writes: list[Write] = []
    for collection in COLLECTIONS:
        docs = desired[collection]
        writes += [SetDocument(collection, doc_id, data) for doc_id, data in sorted(docs.items())]
        stale = existing[collection] - docs.keys()
        writes += [DeleteDocument(collection, doc_id) for doc_id in sorted(stale)]
    return writes


def sync(store: DocumentStore, desired: Documents) -> SyncSummary:
    existing = {collection: store.list_ids(collection) for collection in COLLECTIONS}
    writes = plan_writes(desired, existing)
    store.apply(writes)
    return SyncSummary(
        written={
            c: sum(isinstance(w, SetDocument) and w.collection == c for w in writes)
            for c in COLLECTIONS
        },
        deleted={
            c: sum(isinstance(w, DeleteDocument) and w.collection == c for w in writes)
            for c in COLLECTIONS
        },
    )
