"""Repo implementations without a network: the Firestore document format and the in-memory
transaction semantics. The Firestore repo itself runs in tests_integration/."""

import datetime as dt

import pytest

from app.repo import ProgressTransaction
from app.repo.firestore import attempt_data, live_check_data, progress_data
from app.schemas.content import HallucinationError, Sentence
from app.schemas.firestore import Attempt, LiveCheckSession, Progress
from app.schemas.live_check import WebSource
from app.services.progress import NEW_PROGRESS
from tests.content import CHOICE_ID, LESSON_ID, make_repo

CREATED = dt.datetime(2026, 11, 9, 1, 0, tzinfo=dt.UTC)
ATTEMPT = Attempt(
    exercise_id=CHOICE_ID,
    lesson_id=LESSON_ID,
    type="choice",
    correct=True,
    score=None,
    answer={"type": "choice", "optionId": "b"},
    feedback_text="x",
    xp_gained=10,
    created_at=CREATED,
)


def test_progress_document_is_camel_case_json_with_explicit_null_date() -> None:
    assert progress_data(NEW_PROGRESS) == {
        "xp": 0,
        "streakDays": 0,
        "lastStudiedOn": None,
        "freezeTickets": 0,
        "completedLessonIds": [],
    }
    studied = Progress.model_validate(
        {**progress_data(NEW_PROGRESS), "lastStudiedOn": "2026-11-09"}
    )
    assert progress_data(studied)["lastStudiedOn"] == "2026-11-09"


def test_attempt_document_keeps_created_at_as_a_timestamp() -> None:
    data = attempt_data(ATTEMPT)

    assert data["createdAt"] == CREATED  # a datetime becomes a Firestore timestamp
    assert data["exerciseId"] == CHOICE_ID
    assert data["score"] is None
    assert Attempt.model_validate(data) == ATTEMPT


def test_failed_transaction_writes_nothing() -> None:
    repo = make_repo()

    def work(transaction: ProgressTransaction) -> None:
        transaction.get_progress()
        transaction.add_attempt("a1", ATTEMPT)
        transaction.set_progress(NEW_PROGRESS)
        raise RuntimeError("abort")

    with pytest.raises(RuntimeError, match="abort"):
        repo.run_transaction("uid-1", work)
    assert repo.attempts.get("uid-1", {}) == {}
    assert repo.progress == {}


def test_reads_after_writes_are_rejected_like_firestore() -> None:
    repo = make_repo()

    def work(transaction: ProgressTransaction) -> None:
        transaction.set_progress(NEW_PROGRESS)
        transaction.list_attempts([CHOICE_ID])

    with pytest.raises(RuntimeError, match="read before they write"):
        repo.run_transaction("uid-1", work)


def test_attempts_are_listed_per_learner_and_exercise() -> None:
    repo = make_repo()

    def add(attempt_id: str):
        return lambda transaction: transaction.add_attempt(attempt_id, ATTEMPT)

    repo.run_transaction("uid-1", add("a1"))
    repo.run_transaction("uid-2", add("a2"))

    listed = repo.run_transaction("uid-1", lambda t: t.list_attempts([CHOICE_ID]))
    other_exercise = repo.run_transaction("uid-1", lambda t: t.list_attempts(["t1-l1-q2"]))
    assert listed == [ATTEMPT]
    assert other_exercise == []


def test_attempt_is_found_only_under_its_learner() -> None:
    repo = make_repo()
    repo.run_transaction("uid-1", lambda transaction: transaction.add_attempt("a1", ATTEMPT))

    assert repo.get_attempt("uid-1", "a1") == ATTEMPT
    assert repo.get_attempt("uid-2", "a1") is None
    assert repo.get_attempt("uid-1", "a2") is None


SESSION = LiveCheckSession(
    exercise_id="t3-l1-q1",
    lesson_id="t3-l1",
    prompt="富士山について",
    sentences=[Sentence(index=0, text="一。"), Sentence(index=1, text="二。")],
    errors=[HallucinationError(index=1, error_type="fact", correction="正。", tip="t")],
    sources={"0": [WebSource(title="a", uri="https://a")], "1": []},
    lookups_used=0,
    answered=False,
    created_at=CREATED,
)


def test_live_check_document_keeps_created_at_as_a_timestamp() -> None:
    data = live_check_data(SESSION)

    assert data["createdAt"] == CREATED
    assert data["sources"] == {"0": [{"title": "a", "uri": "https://a"}], "1": []}
    assert LiveCheckSession.model_validate(data) == SESSION


def test_live_check_writes_wait_for_the_commit_and_stay_per_learner() -> None:
    repo = make_repo()
    repo.add_live_check("uid-1", "s1", SESSION)
    answered = SESSION.model_copy(update={"answered": True})

    def work(transaction: ProgressTransaction) -> None:
        assert transaction.get_live_check("s1") == SESSION
        transaction.set_live_check("s1", answered)
        raise RuntimeError("abort")

    with pytest.raises(RuntimeError, match="abort"):
        repo.run_transaction("uid-1", work)
    assert repo.live_checks["uid-1"]["s1"] == SESSION

    repo.run_transaction("uid-1", lambda t: t.set_live_check("s1", answered))
    assert repo.live_checks["uid-1"]["s1"] == answered
    assert repo.run_transaction("uid-2", lambda t: t.get_live_check("s1")) is None


def test_live_check_ids_are_new_and_only_existing_sessions_are_replaced() -> None:
    repo = make_repo()
    repo.add_live_check("uid-1", "s1", SESSION)

    with pytest.raises(ValueError, match="already exists"):
        repo.add_live_check("uid-1", "s1", SESSION)
    with pytest.raises(ValueError, match="does not exist"):
        repo.run_transaction("uid-1", lambda t: t.set_live_check("s2", SESSION))


def test_live_checks_are_counted_per_learner_from_a_time() -> None:
    repo = make_repo()
    repo.add_live_check("uid-1", "s1", SESSION)
    repo.add_live_check(
        "uid-1", "s2", SESSION.model_copy(update={"created_at": CREATED - dt.timedelta(days=1)})
    )

    assert repo.count_live_checks_since("uid-1", CREATED) == 1
    assert repo.count_live_checks_since("uid-1", CREATED - dt.timedelta(days=2)) == 2
    assert repo.count_live_checks_since("uid-2", CREATED) == 0
