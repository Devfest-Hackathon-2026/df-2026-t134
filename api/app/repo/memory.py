"""LearningRepo kept in memory: for tests and for exporting the OpenAPI schema.

Transactions are serialized with a lock and buffer their writes until the work function
returns, so a failing request writes nothing (like Firestore).
"""

import datetime as dt
import threading
from collections.abc import Callable, Collection, Iterable, Mapping

from app.repo import ProgressTransaction
from app.schemas.content import AnswerKey, Exercise, Lesson
from app.schemas.firestore import Attempt, LiveCheckSession, Progress


class _MemoryProgressTransaction:
    def __init__(self, repo: "InMemoryLearningRepo", uid: str) -> None:
        self._repo = repo
        self._uid = uid
        self._progress: Progress | None = None
        self._attempts: dict[str, Attempt] = {}
        self._live_checks: dict[str, LiveCheckSession] = {}

    def _before_writes(self) -> None:
        if self._progress is not None or self._attempts or self._live_checks:
            raise RuntimeError("transactions must read before they write")

    def get_progress(self) -> Progress | None:
        self._before_writes()
        return self._repo.progress.get(self._uid)

    def list_attempts(self, exercise_ids: Collection[str]) -> list[Attempt]:
        self._before_writes()
        attempts = self._repo.attempts.get(self._uid, {}).values()
        return [a for a in attempts if a.exercise_id in exercise_ids]

    def get_live_check(self, session_id: str) -> LiveCheckSession | None:
        self._before_writes()
        return self._repo.live_checks.get(self._uid, {}).get(session_id)

    def set_live_check(self, session_id: str, session: LiveCheckSession) -> None:
        if session_id not in self._repo.live_checks.get(self._uid, {}):
            raise ValueError(f"live check {session_id} does not exist")
        self._live_checks[session_id] = session

    def add_attempt(self, attempt_id: str, attempt: Attempt) -> None:
        if attempt_id in self._attempts or attempt_id in self._repo.attempts.get(self._uid, {}):
            raise ValueError(f"attempt {attempt_id} already exists")
        self._attempts[attempt_id] = attempt

    def set_progress(self, progress: Progress) -> None:
        self._progress = progress

    def commit(self) -> None:
        self._repo.attempts.setdefault(self._uid, {}).update(self._attempts)
        self._repo.live_checks.setdefault(self._uid, {}).update(self._live_checks)
        if self._progress is not None:
            self._repo.progress[self._uid] = self._progress


class InMemoryLearningRepo:
    def __init__(
        self,
        lessons: Iterable[Lesson] = (),
        exercises: Iterable[Exercise] = (),
        answer_keys: Mapping[str, AnswerKey] | None = None,
    ) -> None:
        self.lessons = {lesson.id: lesson for lesson in lessons}
        self.exercises = {exercise.id: exercise for exercise in exercises}
        self.answer_keys = dict(answer_keys or {})
        # progress[uid] and attempts[uid][attempt_id], as in Firestore.
        self.progress: dict[str, Progress] = {}
        self.attempts: dict[str, dict[str, Attempt]] = {}
        # live_checks[uid][session_id], as in Firestore.
        self.live_checks: dict[str, dict[str, LiveCheckSession]] = {}
        self._lock = threading.Lock()

    def get_lesson(self, lesson_id: str) -> Lesson | None:
        return self.lessons.get(lesson_id)

    def get_exercise(self, exercise_id: str) -> Exercise | None:
        return self.exercises.get(exercise_id)

    def get_answer_key(self, exercise_id: str) -> AnswerKey | None:
        return self.answer_keys.get(exercise_id)

    def get_attempt(self, uid: str, attempt_id: str) -> Attempt | None:
        return self.attempts.get(uid, {}).get(attempt_id)

    def add_live_check(self, uid: str, session_id: str, session: LiveCheckSession) -> None:
        with self._lock:
            sessions = self.live_checks.setdefault(uid, {})
            if session_id in sessions:
                raise ValueError(f"live check {session_id} already exists")
            sessions[session_id] = session

    def count_live_checks_since(self, uid: str, since: dt.datetime) -> int:
        return sum(s.created_at >= since for s in self.live_checks.get(uid, {}).values())

    def run_transaction[T](self, uid: str, work: Callable[[ProgressTransaction], T]) -> T:
        with self._lock:
            transaction = _MemoryProgressTransaction(self, uid)
            result = work(transaction)
            transaction.commit()
            return result
