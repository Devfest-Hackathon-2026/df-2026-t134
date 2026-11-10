import datetime as dt

import pytest

from app.schemas.firestore import Attempt, Progress
from app.services.progress import (
    NEW_PROGRESS,
    PROMPT_PASSING_SCORE,
    XP_FIRST_CORRECT_ANSWER,
    Streak,
    add_xp,
    answer_xp,
    complete_lesson,
    missed_school_days,
    next_streak,
    prompt_xp,
    tokyo_date,
)

MON = dt.date(2026, 11, 2)
TUE, WED, THU, FRI, SAT, SUN = (MON + dt.timedelta(days=n) for n in range(1, 7))
NEXT_MON = MON + dt.timedelta(days=7)
NEXT_TUE = MON + dt.timedelta(days=8)


def _progress(
    *,
    xp: int = 0,
    streak: int = 0,
    last: dt.date | None = None,
    tickets: int = 0,
    completed: tuple[str, ...] = (),
) -> Progress:
    return Progress(
        xp=xp,
        streak_days=streak,
        last_studied_on=last,
        freeze_tickets=tickets,
        completed_lesson_ids=list(completed),
    )


def _attempt(correct: bool) -> Attempt:
    return Attempt(
        exercise_id="u1-l1-q1",
        lesson_id="u1-l1",
        type="choice",
        correct=correct,
        score=None,
        answer={"type": "choice", "optionId": "a"},
        feedback_text="x",
        xp_gained=0,
        created_at=dt.datetime(2026, 11, 2, tzinfo=dt.UTC),
    )


def test_week_constants_are_the_expected_weekdays() -> None:
    assert [d.strftime("%a") for d in (MON, FRI, SAT, SUN, NEXT_MON)] == [
        "Mon",
        "Fri",
        "Sat",
        "Sun",
        "Mon",
    ]


# ---- XP ---------------------------------------------------------------------------------


def test_first_correct_answer_earns_10_xp() -> None:
    assert answer_xp(True, []) == 10


def test_correct_after_only_wrong_attempts_still_earns_xp() -> None:
    assert answer_xp(True, [_attempt(False), _attempt(False)]) == 10


def test_correct_again_after_a_correct_attempt_earns_nothing() -> None:
    assert answer_xp(True, [_attempt(False), _attempt(True)]) == 0


@pytest.mark.parametrize("earlier", [[], [_attempt(True)]])
def test_wrong_answer_earns_nothing(earlier: list[Attempt]) -> None:
    assert answer_xp(False, earlier) == 0


def test_add_xp_keeps_everything_else() -> None:
    progress = _progress(xp=30, streak=2, last=MON, tickets=1, completed=("u1-l1",))

    assert add_xp(progress, 10) == _progress(
        xp=40, streak=2, last=MON, tickets=1, completed=("u1-l1",)
    )


def test_first_completion_earns_20_xp_and_records_the_lesson() -> None:
    completion = complete_lesson(_progress(xp=10), "u1-l1", MON)

    assert completion.xp_gained == 20
    assert completion.progress == _progress(xp=30, streak=1, last=MON, completed=("u1-l1",))


def test_repeated_completion_earns_nothing_and_does_not_duplicate_the_lesson() -> None:
    progress = _progress(xp=30, streak=1, last=MON, completed=("u1-l1",))

    completion = complete_lesson(progress, "u1-l1", TUE)

    assert completion.xp_gained == 0
    assert completion.progress == _progress(xp=30, streak=2, last=TUE, completed=("u1-l1",))


def test_new_learner_completion_starts_from_empty_progress() -> None:
    completion = complete_lesson(NEW_PROGRESS, "u1-l1", MON)

    assert completion.progress == _progress(xp=20, streak=1, last=MON, completed=("u1-l1",))


# ---- Dates ------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("instant", "expected"),
    [
        (dt.datetime(2026, 11, 2, 14, 59, tzinfo=dt.UTC), MON),  # 23:59 JST
        (dt.datetime(2026, 11, 2, 15, 0, tzinfo=dt.UTC), TUE),  # 00:00 JST
        (dt.datetime(2026, 11, 3, 0, 30, tzinfo=dt.timezone(dt.timedelta(hours=9))), TUE),
    ],
)
def test_tokyo_date_switches_at_midnight_in_japan(instant: dt.datetime, expected: dt.date) -> None:
    assert tokyo_date(instant) == expected


def test_naive_datetime_is_rejected() -> None:
    with pytest.raises(ValueError, match="timezone-aware"):
        tokyo_date(dt.datetime(2026, 11, 2, 12, 0))


@pytest.mark.parametrize(
    ("last", "today", "missed"),
    [
        (MON, TUE, 0),
        (MON, WED, 1),
        (MON, FRI, 3),
        (FRI, NEXT_MON, 0),  # only the weekend in between
        (THU, NEXT_MON, 1),  # Friday
        (FRI, NEXT_TUE, 1),  # Monday
        (SAT, NEXT_MON, 0),
        (MON, NEXT_MON, 4),  # Tue-Fri
        (MON, MON + dt.timedelta(days=28), 19),
    ],
)
def test_missed_school_days_skip_weekends(last: dt.date, today: dt.date, missed: int) -> None:
    assert missed_school_days(last, today) == missed


# ---- Streak -----------------------------------------------------------------------------


def test_first_ever_study_starts_the_streak_at_1() -> None:
    assert next_streak(NEW_PROGRESS, MON) == Streak(days=1, freeze_tickets=0)


def test_same_day_keeps_the_streak() -> None:
    assert next_streak(_progress(streak=3, last=MON, tickets=1), MON) == Streak(3, 1)


def test_next_day_extends_the_streak() -> None:
    assert next_streak(_progress(streak=3, last=MON), TUE) == Streak(4, 0)


def test_saturday_after_friday_is_the_next_day() -> None:
    assert next_streak(_progress(streak=3, last=FRI), SAT) == Streak(4, 0)


def test_weekend_gap_keeps_the_streak_without_tickets() -> None:
    assert next_streak(_progress(streak=3, last=FRI, tickets=0), NEXT_MON) == Streak(4, 0)


def test_missed_school_day_consumes_a_freeze_ticket() -> None:
    assert next_streak(_progress(streak=3, last=MON, tickets=2), WED) == Streak(4, 1)


def test_missed_days_consume_one_ticket_each() -> None:
    # Missed Tue, Wed, Thu.
    assert next_streak(_progress(streak=3, last=MON, tickets=3), FRI) == Streak(4, 0)


def test_missed_days_over_a_weekend_count_only_school_days() -> None:
    # Missed Fri and Mon; Sat and Sun do not count.
    assert next_streak(_progress(streak=3, last=THU, tickets=2), NEXT_TUE) == Streak(4, 0)


def test_not_enough_tickets_resets_the_streak_and_keeps_the_tickets() -> None:
    assert next_streak(_progress(streak=7, last=MON, tickets=2), FRI) == Streak(1, 2)


def test_no_tickets_resets_the_streak() -> None:
    assert next_streak(_progress(streak=7, last=MON), WED) == Streak(1, 0)


def test_reaching_5_days_grants_a_ticket() -> None:
    assert next_streak(_progress(streak=4, last=MON), TUE) == Streak(5, 1)


def test_reaching_10_days_grants_another_ticket() -> None:
    assert next_streak(_progress(streak=9, last=MON, tickets=1), TUE) == Streak(10, 2)


def test_tickets_are_capped_at_3() -> None:
    assert next_streak(_progress(streak=14, last=MON, tickets=3), TUE) == Streak(15, 3)


def test_ticket_is_consumed_before_the_multiple_of_5_grant() -> None:
    assert next_streak(_progress(streak=4, last=MON, tickets=1), WED) == Streak(5, 1)


@pytest.mark.parametrize("streak", [5, 6])
def test_no_grant_without_reaching_a_new_multiple_of_5(streak: int) -> None:
    # Same day: unchanged. Reset: back to 1.
    assert next_streak(_progress(streak=streak, last=MON, tickets=1), MON) == Streak(streak, 1)
    assert next_streak(_progress(streak=streak, last=MON), FRI) == Streak(1, 0)


def test_study_day_in_the_future_is_an_impossible_state() -> None:
    with pytest.raises(ValueError, match="before the last study day"):
        next_streak(_progress(streak=1, last=TUE), MON)


def test_completion_applies_the_streak_rules() -> None:
    progress = _progress(xp=100, streak=4, last=MON, tickets=1, completed=("u1-l1",))

    completion = complete_lesson(progress, "u1-l2", WED)

    assert completion.progress == _progress(
        xp=120, streak=5, last=WED, tickets=1, completed=("u1-l1", "u1-l2")
    )


def _prompt_attempt(score: int) -> Attempt:
    return Attempt(
        exercise_id="u2-l1-q1",
        lesson_id="u2-l1",
        type="prompt",
        correct=None,
        score=score,
        answer={"type": "prompt", "prompt": "x"},
        feedback_text="x",
        xp_gained=0,
        created_at=dt.datetime(2026, 11, 2, tzinfo=dt.UTC),
    )


@pytest.mark.parametrize(
    ("score", "earlier", "xp"),
    [
        (PROMPT_PASSING_SCORE, [], XP_FIRST_CORRECT_ANSWER),
        (10, [3, 5], XP_FIRST_CORRECT_ANSWER),
        (PROMPT_PASSING_SCORE - 1, [], 0),
        (9, [PROMPT_PASSING_SCORE], 0),
        (0, [], 0),
    ],
    ids=["first pass", "pass after failures", "below passing", "passed before", "zero"],
)
def test_prompt_earns_xp_on_the_first_passing_score(
    score: int, earlier: list[int], xp: int
) -> None:
    assert prompt_xp(score, [_prompt_attempt(s) for s in earlier]) == xp


@pytest.mark.parametrize("score", [-1, 11])
def test_prompt_score_outside_0_to_10_is_rejected(score: int) -> None:
    with pytest.raises(ValueError):
        prompt_xp(score, [])
