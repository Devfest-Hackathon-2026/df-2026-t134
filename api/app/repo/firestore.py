"""LearningRepo on Cloud Firestore (Admin SDK client, or the emulator via FIRESTORE_EMULATOR_HOST).

Document format (shared with tools/content_tools/seed.py and the app):
- content documents: id = model id, data = model_dump(mode="json", exclude_none=True)
- progress/{uid}: Progress.model_dump(mode="json") (lastStudiedOn is "YYYY-MM-DD" or null)
- attempts/{uid}/items/{attemptId}: Attempt dump with createdAt as a Firestore timestamp
- liveChecks/{uid}/items/{sessionId}: LiveCheckSession dump, createdAt as a timestamp
"""

import datetime as dt
import random
import time
from collections.abc import Callable, Collection
from typing import Any

import firebase_admin
from firebase_admin import firestore
from google.api_core.exceptions import Aborted
from google.auth.credentials import AnonymousCredentials
from google.cloud.firestore import (
    Client,
    CollectionReference,
    DocumentReference,
    DocumentSnapshot,
    Transaction,
    transactional,
)
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import TypeAdapter

from app.repo import ProgressTransaction
from app.schemas.content import AnswerKey, Exercise, Lesson
from app.schemas.firestore import (
    ANSWER_KEYS_COLLECTION,
    ATTEMPT_ITEMS_SUBCOLLECTION,
    ATTEMPTS_COLLECTION,
    EXERCISES_COLLECTION,
    LESSONS_COLLECTION,
    LIVE_CHECK_ITEMS_SUBCOLLECTION,
    LIVE_CHECKS_COLLECTION,
    PROGRESS_COLLECTION,
    Attempt,
    LiveCheckSession,
    Progress,
)

# Firestore limits an "in" filter to 30 values; a lesson has at most 12 exercises.
MAX_IN_FILTER_VALUES = 30
# Concurrent requests of one learner contend on progress/{uid}. Firestore then aborts a
# transaction on a read ("lock timeout") or on commit; the SDK retries only the commit, and
# without delay. So the repo retries the whole transaction itself, with jittered backoff.
TRANSACTION_MAX_ATTEMPTS = 8
RETRY_BASE_SECONDS = 0.05
RETRY_MAX_SECONDS = 1.0

_exercise_adapter: TypeAdapter[Any] = TypeAdapter(Exercise)
_answer_key_adapter: TypeAdapter[Any] = TypeAdapter(AnswerKey)


def firestore_client(firebase_app: firebase_admin.App) -> Client:
    """Production client with the app's credentials (Application Default Credentials)."""
    return firestore.client(firebase_app)


def emulator_firestore_client(firebase_app: firebase_admin.App) -> Client:
    """Client for the emulator named by FIRESTORE_EMULATOR_HOST, which needs no credentials
    (the app's credentials are not resolved, so local runs need no ADC)."""
    return Client(project=firebase_app.project_id, credentials=AnonymousCredentials())


def progress_data(progress: Progress) -> dict[str, object]:
    return progress.model_dump(mode="json")


def attempt_data(attempt: Attempt) -> dict[str, object]:
    # Python mode keeps createdAt a datetime, which Firestore stores as a timestamp.
    return attempt.model_dump(mode="python")


def live_check_data(session: LiveCheckSession) -> dict[str, object]:
    # Python mode keeps createdAt a datetime, which Firestore stores as a timestamp.
    return session.model_dump(mode="python")


def _live_check_items(client: Client, uid: str) -> CollectionReference:
    return (
        client.collection(LIVE_CHECKS_COLLECTION)
        .document(uid)
        .collection(LIVE_CHECK_ITEMS_SUBCOLLECTION)
    )


def _attempt_items(client: Client, uid: str) -> CollectionReference:
    return (
        client.collection(ATTEMPTS_COLLECTION).document(uid).collection(ATTEMPT_ITEMS_SUBCOLLECTION)
    )


def _data(snapshot: DocumentSnapshot) -> dict[str, Any] | None:
    return snapshot.to_dict() if snapshot.exists else None


def _content[T](data: dict[str, Any] | None, doc_id: str, parse: Callable[[object], T]) -> T | None:
    if data is None:
        return None
    model = parse(data)
    if getattr(model, "id", doc_id) != doc_id:
        raise ValueError(f"document {doc_id} has a different id field")
    return model


class _FirestoreProgressTransaction:
    def __init__(self, client: Client, transaction: Transaction, uid: str) -> None:
        self._transaction = transaction
        self._progress_ref: DocumentReference = client.collection(PROGRESS_COLLECTION).document(uid)
        self._attempts = _attempt_items(client, uid)
        self._live_checks = _live_check_items(client, uid)

    def get_progress(self) -> Progress | None:
        data = _data(self._progress_ref.get(transaction=self._transaction))
        return None if data is None else Progress.model_validate(data)

    def list_attempts(self, exercise_ids: Collection[str]) -> list[Attempt]:
        if not 1 <= len(exercise_ids) <= MAX_IN_FILTER_VALUES:
            raise ValueError(f"list_attempts takes 1..{MAX_IN_FILTER_VALUES} exercise ids")
        query = self._attempts.where(filter=FieldFilter("exerciseId", "in", list(exercise_ids)))
        return [
            Attempt.model_validate(snapshot.to_dict())
            for snapshot in query.stream(transaction=self._transaction)
        ]

    def get_live_check(self, session_id: str) -> LiveCheckSession | None:
        data = _data(self._live_checks.document(session_id).get(transaction=self._transaction))
        return None if data is None else LiveCheckSession.model_validate(data)

    def set_live_check(self, session_id: str, session: LiveCheckSession) -> None:
        # update() fails when the document does not exist, like the memory repo.
        self._transaction.update(self._live_checks.document(session_id), live_check_data(session))

    def add_attempt(self, attempt_id: str, attempt: Attempt) -> None:
        self._transaction.create(self._attempts.document(attempt_id), attempt_data(attempt))

    def set_progress(self, progress: Progress) -> None:
        self._transaction.set(self._progress_ref, progress_data(progress))


class FirestoreLearningRepo:
    def __init__(self, client: Client) -> None:
        self._client = client

    def _get(self, collection: str, doc_id: str) -> dict[str, Any] | None:
        return _data(self._client.collection(collection).document(doc_id).get())

    def get_lesson(self, lesson_id: str) -> Lesson | None:
        return _content(self._get(LESSONS_COLLECTION, lesson_id), lesson_id, Lesson.model_validate)

    def get_exercise(self, exercise_id: str) -> Exercise | None:
        data = self._get(EXERCISES_COLLECTION, exercise_id)
        return _content(data, exercise_id, _exercise_adapter.validate_python)

    def get_answer_key(self, exercise_id: str) -> AnswerKey | None:
        # Answer keys have no id field; they are stored under the exercise id.
        data = self._get(ANSWER_KEYS_COLLECTION, exercise_id)
        return _content(data, exercise_id, _answer_key_adapter.validate_python)

    def get_attempt(self, uid: str, attempt_id: str) -> Attempt | None:
        data = _data(_attempt_items(self._client, uid).document(attempt_id).get())
        return None if data is None else Attempt.model_validate(data)

    def add_live_check(self, uid: str, session_id: str, session: LiveCheckSession) -> None:
        _live_check_items(self._client, uid).document(session_id).create(live_check_data(session))

    def count_live_checks_since(self, uid: str, since: dt.datetime) -> int:
        query = _live_check_items(self._client, uid).where(
            filter=FieldFilter("createdAt", ">=", since)
        )
        [[result]] = query.count().get()
        return int(result.value)

    def run_transaction[T](self, uid: str, work: Callable[[ProgressTransaction], T]) -> T:
        @transactional
        def run(transaction: Transaction) -> T:
            return work(_FirestoreProgressTransaction(self._client, transaction, uid))

        for attempt in range(1, TRANSACTION_MAX_ATTEMPTS + 1):
            try:
                # One SDK attempt each: every retry goes through the backoff below.
                return run(self._client.transaction(max_attempts=1))
            except (Aborted, ValueError) as error:
                if not _is_contention(error) or attempt == TRANSACTION_MAX_ATTEMPTS:
                    raise
            delay = min(RETRY_MAX_SECONDS, RETRY_BASE_SECONDS * 2**attempt)
            time.sleep(random.uniform(0, delay))
        raise AssertionError("unreachable")


def _is_contention(error: Exception) -> bool:
    """Aborted from a read, or the SDK's ValueError wrapping an aborted commit."""
    return isinstance(error, Aborted) or isinstance(error.__cause__, Aborted)
