"""Use case behind POST /v1/prompt/evaluate (Q4, requirements §5.3 and §8.4).

1. Validate the exercise and the length of the prompt (400 / 404).
2. Block prompts with personal information before anything leaves the server (§11).
3. Grade with the model, outside the transaction (it is slow and must not be retried).
4. Record the attempt and the XP in one transaction, like /v1/answers.
"""

import datetime as dt
import logging

from app.ai import AiBlocked, AiUnavailable, JsonGenerator
from app.errors import ApiError
from app.repo import LearningRepo, ProgressTransaction
from app.safety.personal_info import PersonalInfoKind, find_personal_info
from app.schemas.common import ProgressSnapshot
from app.schemas.content import PromptAnswerKey, PromptExercise
from app.schemas.firestore import Attempt
from app.schemas.prompt import (
    EvaluatePromptRequest,
    EvaluatePromptResponse,
    PromptBlocked,
    PromptEvaluated,
)
from app.services import progress as rules
from app.services.prompt_rubric import RubricGrading, grading_request

_logger = logging.getLogger("app.prompt")

_KIND_LABELS: dict[PersonalInfoKind, str] = {
    "email": "メールアドレス",
    "phone": "電話番号",
    "postal_code": "郵便番号",
    "address": "住所",
    "name": "名前",
}

INAPPROPRIATE_MESSAGE = (
    "AI に送るのにふさわしくない言葉が入っているかもしれません。"
    "言葉を変えて、もう一度書いてみよう。"
)


def personal_info_message(kinds: list[PersonalInfoKind]) -> str:
    if not kinds:
        raise ValueError("kinds must not be empty")
    labels = "・".join(_KIND_LABELS[kind] for kind in kinds)
    return (
        f"{labels}のような個人情報が入っているみたい。AI に個人情報を送るのはやめておこう。"
        "その部分を消すか「〇〇」に置きかえてから、もう一度送ってね。"
    )


def evaluate_prompt(
    repo: LearningRepo,
    generator: JsonGenerator,
    uid: str,
    request: EvaluatePromptRequest,
    now: dt.datetime,
    attempt_id: str,
) -> EvaluatePromptResponse:
    exercise = repo.get_exercise(request.exercise_id)
    if exercise is None:
        raise ApiError(404, "not_found", "Exercise not found")
    if not isinstance(exercise, PromptExercise):
        raise ApiError(400, "bad_request", f"{exercise.type} exercises are graded by /v1/answers")
    if len(request.prompt) > exercise.max_length:
        raise ApiError(
            400, "bad_request", f"prompt must be at most {exercise.max_length} characters"
        )

    kinds = find_personal_info(request.prompt)
    if kinds:
        _log_blocked(exercise.id, "personal_info", kinds)
        return PromptBlocked(
            status="blocked", reasons=["personal_info"], message=personal_info_message(kinds)
        )

    key = repo.get_answer_key(exercise.id)
    if key is None:
        raise LookupError(f"answer key of exercise {exercise.id} is missing")
    if not isinstance(key, PromptAnswerKey):
        raise ValueError(f"answer key of prompt exercise {exercise.id} has type {key.type}")

    try:
        grading = generator.generate(grading_request(exercise, key, request.prompt), RubricGrading)
    except AiBlocked:
        _log_blocked(exercise.id, "inappropriate", [])
        return PromptBlocked(
            status="blocked", reasons=["inappropriate"], message=INAPPROPRIATE_MESSAGE
        )
    except AiUnavailable as exc:
        _logger.warning(
            "prompt grader unavailable",
            extra={"json_fields": {"exerciseId": exercise.id, "reason": str(exc)}},
        )
        raise ApiError(
            503, "upstream_unavailable", "The prompt grader is not available right now"
        ) from exc

    scores = grading.scores
    total = scores.purpose + scores.context + scores.constraints + scores.format + scores.safety
    feedback_text = "\n".join([grading.good_point, *grading.improvements, grading.hint])

    def record(transaction: ProgressTransaction) -> ProgressSnapshot:
        progress = transaction.get_progress() or rules.NEW_PROGRESS
        xp = rules.prompt_xp(total, transaction.list_attempts([exercise.id]))
        updated = rules.add_xp(progress, xp)
        attempt = Attempt(
            exercise_id=exercise.id,
            lesson_id=exercise.lesson_id,
            type="prompt",
            correct=None,
            score=total,
            answer={"type": "prompt", "prompt": request.prompt},
            feedback_text=feedback_text,
            xp_gained=xp,
            created_at=now,
        )
        transaction.add_attempt(attempt_id, attempt)
        # Written even when unchanged so that concurrent answers of one learner conflict.
        transaction.set_progress(updated)
        return rules.snapshot(updated, xp)

    snapshot = repo.run_transaction(uid, record)
    # No prompt text or feedback: learners are minors and the ids are enough to debug.
    _logger.info(
        "prompt evaluated",
        extra={
            "json_fields": {
                "attemptId": attempt_id,
                "exerciseId": exercise.id,
                "total": total,
                "xpGained": snapshot.xp_gained,
            }
        },
    )
    return PromptEvaluated(
        status="evaluated",
        attempt_id=attempt_id,
        total=total,
        scores=scores,
        good_point=grading.good_point,
        improvements=grading.improvements,
        hint=grading.hint,
        progress=snapshot,
    )


def _log_blocked(exercise_id: str, reason: str, kinds: list[PersonalInfoKind]) -> None:
    # The kinds of personal information, never the matched text.
    _logger.info(
        "prompt blocked",
        extra={"json_fields": {"exerciseId": exercise_id, "reason": reason, "kinds": kinds}},
    )
