"""XP and streak rules (pure functions; the server is the only writer of progress).

- A correct answer earns XP only on the learner's first correct attempt at that exercise.
- A graded prompt (Q4) earns the same XP on the learner's first attempt that reaches the
  passing score at that exercise.
- Completing a lesson earns XP the first time only; every completion counts as a study day.
- Streak days use the calendar date in Asia/Tokyo. Saturdays and Sundays are never "missed":
  a gap of only weekend days keeps the streak, missed school days need one freeze ticket each,
  otherwise the streak starts again at 1. Reaching a multiple of 5 days grants a ticket.
"""

import datetime as dt
from collections.abc import Sequence
from dataclasses import dataclass

from app.schemas.common import ProgressSnapshot
from app.schemas.firestore import Attempt, Progress

XP_FIRST_CORRECT_ANSWER = 10
XP_FIRST_LESSON_COMPLETION = 20
# Out of 10. Also the score from which the prompt is good enough to run (requirements §5.3).
PROMPT_PASSING_SCORE = 6
FREEZE_TICKET_EVERY_STREAK_DAYS = 5
MAX_FREEZE_TICKETS = 3

# Japan has no daylight saving time, so a fixed offset is exact (and needs no tz database).
TOKYO = dt.timezone(dt.timedelta(hours=9), "Asia/Tokyo")
_SATURDAY = 5

NEW_PROGRESS = Progress(
    xp=0, streak_days=0, last_studied_on=None, freeze_tickets=0, completed_lesson_ids=[]
)


def tokyo_date(now: dt.datetime) -> dt.date:
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")
    return now.astimezone(TOKYO).date()


def answer_xp(correct: bool, earlier_attempts: Sequence[Attempt]) -> int:
    """XP for an answer, given the learner's earlier attempts at the same exercise."""
    if correct and not any(attempt.correct for attempt in earlier_attempts):
        return XP_FIRST_CORRECT_ANSWER
    return 0


def prompt_xp(score: int, earlier_attempts: Sequence[Attempt]) -> int:
    """XP for a graded prompt, given the learner's earlier attempts at the same exercise."""
    if not 0 <= score <= 10:
        raise ValueError("score must be between 0 and 10")
    if score >= PROMPT_PASSING_SCORE and not any(
        attempt.score is not None and attempt.score >= PROMPT_PASSING_SCORE
        for attempt in earlier_attempts
    ):
        return XP_FIRST_CORRECT_ANSWER
    return 0


def add_xp(progress: Progress, xp: int) -> Progress:
    return _replace(progress, xp=progress.xp + xp)


def missed_school_days(last_studied_on: dt.date, today: dt.date) -> int:
    """Weekdays strictly between the two dates."""
    days = (today - last_studied_on).days - 1
    between = (last_studied_on + dt.timedelta(days=offset) for offset in range(1, days + 1))
    return sum(day.weekday() < _SATURDAY for day in between)


@dataclass(frozen=True, slots=True)
class Streak:
    days: int
    freeze_tickets: int


def next_streak(progress: Progress, today: dt.date) -> Streak:
    """The streak after studying today."""
    last = progress.last_studied_on
    current = Streak(progress.streak_days, progress.freeze_tickets)
    if last is None:
        return _extended(Streak(0, current.freeze_tickets))
    if today < last:
        raise ValueError("today is before the last study day")
    if today == last:
        return current
    missed = missed_school_days(last, today)
    if missed == 0:
        return _extended(current)
    if current.freeze_tickets >= missed:
        return _extended(Streak(current.days, current.freeze_tickets - missed))
    return Streak(1, current.freeze_tickets)


def _extended(streak: Streak) -> Streak:
    days = streak.days + 1
    tickets = streak.freeze_tickets
    if days % FREEZE_TICKET_EVERY_STREAK_DAYS == 0:
        tickets = min(tickets + 1, MAX_FREEZE_TICKETS)
    return Streak(days, tickets)


@dataclass(frozen=True, slots=True)
class LessonCompletion:
    progress: Progress
    xp_gained: int


def complete_lesson(progress: Progress, lesson_id: str, today: dt.date) -> LessonCompletion:
    first_time = lesson_id not in progress.completed_lesson_ids
    xp = XP_FIRST_LESSON_COMPLETION if first_time else 0
    completed = progress.completed_lesson_ids
    if first_time:
        completed = [*completed, lesson_id]
    streak = next_streak(progress, today)
    updated = _replace(
        progress,
        xp=progress.xp + xp,
        streak_days=streak.days,
        freeze_tickets=streak.freeze_tickets,
        last_studied_on=today,
        completed_lesson_ids=completed,
    )
    return LessonCompletion(updated, xp)


def snapshot(progress: Progress, xp_gained: int) -> ProgressSnapshot:
    return ProgressSnapshot(xp=progress.xp, xp_gained=xp_gained, streak_days=progress.streak_days)


def _replace(progress: Progress, **changes: object) -> Progress:
    # Rebuild instead of model_copy so the constraints (e.g. at most 3 tickets) are checked.
    return Progress.model_validate({**dict(progress), **changes})
