"""Use cases behind POST /v1/answers and POST /v1/lessons/{lessonId}/complete.

Content is read outside the transaction (it does not change per learner). Everything that
depends on the learner's progress and attempts is read, computed and written in one
transaction, so concurrent requests cannot lose XP or award first-correct XP twice.
"""

import datetime as dt
import logging

from app.errors import ApiError, not_implemented
from app.repo import LearningRepo, ProgressTransaction
from app.schemas.answers import LiveCheckAnswer, SubmitAnswerRequest, SubmitAnswerResponse
from app.schemas.common import ProgressSnapshot
from app.schemas.content import LiveCheckExercise
from app.schemas.firestore import Attempt
from app.schemas.lessons import CompleteLessonResponse
from app.services import progress as rules
from app.services.grading import answer_problem, grade
from app.services.live_check import submit_live_check_answer

_logger = logging.getLogger("app.answers")


def submit_answer(
    repo: LearningRepo,
    uid: str,
    request: SubmitAnswerRequest,
    now: dt.datetime,
    attempt_id: str,
) -> SubmitAnswerResponse:
    exercise = repo.get_exercise(request.exercise_id)
    if exercise is None:
        raise ApiError(404, "not_found", "Exercise not found")
    if exercise.type == "agent":
        raise not_implemented("the agent builder PR")
    problem = answer_problem(exercise, request.answer)
    if problem is not None:
        raise ApiError(400, "bad_request", problem)
    if isinstance(exercise, LiveCheckExercise) and isinstance(request.answer, LiveCheckAnswer):
        # Graded against the learner's session instead of the answer key.
        return submit_live_check_answer(repo, uid, exercise, request.answer, now, attempt_id)
    key = repo.get_answer_key(exercise.id)
    if key is None:
        raise LookupError(f"answer key of exercise {exercise.id} is missing")
    graded = grade(key, request.answer)

    def record(transaction: ProgressTransaction) -> ProgressSnapshot:
        progress = transaction.get_progress() or rules.NEW_PROGRESS
        xp = rules.answer_xp(graded.correct, transaction.list_attempts([exercise.id]))
        updated = rules.add_xp(progress, xp)
        attempt = Attempt(
            exercise_id=exercise.id,
            lesson_id=exercise.lesson_id,
            type=exercise.type,
            correct=graded.correct,
            score=None,
            answer=request.answer.model_dump(mode="json"),
            feedback_text=graded.feedback_text,
            xp_gained=xp,
            created_at=now,
        )
        transaction.add_attempt(attempt_id, attempt)
        # Written even when unchanged so that concurrent answers of one learner conflict.
        transaction.set_progress(updated)
        return rules.snapshot(updated, xp)

    snapshot = repo.run_transaction(uid, record)
    # No answer contents: learners are minors and the ids are enough to debug.
    _logger.info(
        "answer graded",
        extra={
            "json_fields": {
                "attemptId": attempt_id,
                "exerciseId": exercise.id,
                "exerciseType": exercise.type,
                "correct": graded.correct,
                "xpGained": snapshot.xp_gained,
            }
        },
    )
    return SubmitAnswerResponse(
        attempt_id=attempt_id, correct=graded.correct, result=graded.result, progress=snapshot
    )


def complete_lesson(
    repo: LearningRepo, uid: str, lesson_id: str, now: dt.datetime
) -> CompleteLessonResponse:
    lesson = repo.get_lesson(lesson_id)
    if lesson is None:
        raise ApiError(404, "not_found", "Lesson not found")
    today = rules.tokyo_date(now)

    def record(transaction: ProgressTransaction) -> ProgressSnapshot:
        progress = transaction.get_progress() or rules.NEW_PROGRESS
        attempted = {a.exercise_id for a in transaction.list_attempts(lesson.exercise_ids)}
        if not attempted.issuperset(lesson.exercise_ids):
            raise ApiError(409, "conflict", "Every exercise of the lesson needs an answer first")
        completion = rules.complete_lesson(progress, lesson.id, today)
        transaction.set_progress(completion.progress)
        return rules.snapshot(completion.progress, completion.xp_gained)

    return CompleteLessonResponse(lesson_id=lesson.id, progress=repo.run_transaction(uid, record))
