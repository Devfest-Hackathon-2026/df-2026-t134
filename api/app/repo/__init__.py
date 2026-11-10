"""Data access for the learning API (Firestore in production, in memory in tests).

Services depend only on the protocols below. Implementations parse every document with the
contract models, so malformed data raises instead of flowing into the grading logic.
"""

import datetime as dt
from collections.abc import Callable, Collection
from typing import Protocol

from app.schemas.content import AnswerKey, Exercise, Lesson
from app.schemas.firestore import Attempt, LiveCheckSession, Progress


class ProgressTransaction(Protocol):
    """The reads and writes of one learner inside one atomic transaction.

    Every read must come before the first write (a Firestore rule). Writes take effect only
    when the transaction commits; the work function may run more than once on contention.
    """

    def get_progress(self) -> Progress | None:
        """progress/{uid}, or None for a learner who has none yet."""
        ...

    def list_attempts(self, exercise_ids: Collection[str]) -> list[Attempt]:
        """The learner's attempts at any of these exercises (at most 30 ids)."""
        ...

    def get_live_check(self, session_id: str) -> LiveCheckSession | None:
        """liveChecks/{uid}/items/{sessionId}: only the learner's own sessions are found."""
        ...

    def add_attempt(self, attempt_id: str, attempt: Attempt) -> None: ...

    def set_progress(self, progress: Progress) -> None: ...

    def set_live_check(self, session_id: str, session: LiveCheckSession) -> None:
        """Replace an existing session of the learner (lookups used, answered)."""
        ...


class LearningRepo(Protocol):
    def get_lesson(self, lesson_id: str) -> Lesson | None: ...

    def get_exercise(self, exercise_id: str) -> Exercise | None: ...

    def get_answer_key(self, exercise_id: str) -> AnswerKey | None: ...

    def get_attempt(self, uid: str, attempt_id: str) -> Attempt | None:
        """attempts/{uid}/items/{attemptId}: only the learner's own attempts are found."""
        ...

    def add_live_check(self, uid: str, session_id: str, session: LiveCheckSession) -> None:
        """Create liveChecks/{uid}/items/{sessionId}; the id must be new."""
        ...

    def count_live_checks_since(self, uid: str, since: dt.datetime) -> int:
        """How many sessions the learner started at or after since."""
        ...

    def run_transaction[T](self, uid: str, work: Callable[[ProgressTransaction], T]) -> T:
        """Run work atomically against the learner's progress, attempts and live check
        sessions; return its result.

        Exceptions raised by work abort the transaction (nothing is written) and propagate.
        """
        ...
