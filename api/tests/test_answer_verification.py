import pytest

from app.schemas.answers import HallucinationAnswer
from app.schemas.content import HallucinationAnswerKey
from app.services import live_check
from app.services.grading import grade_hallucination


def test_server_choice_includes_clean_and_all_configured_error_counts(monkeypatch):
    seen_bounds = []
    for count in range(3):

        def selected(upper, value=count):
            seen_bounds.append(upper)
            return value

        monkeypatch.setattr(live_check.secrets, "randbelow", selected)
        assert live_check.choose_error_count(2) == count
    assert seen_bounds == [3, 3, 3]


@pytest.mark.parametrize("indexes,correct", [([], True), ([0], False)])
def test_authored_clean_answer_is_graded_and_has_feedback(indexes, correct):
    graded = grade_hallucination(
        HallucinationAnswerKey(type="hallucination", errors=[]),
        HallucinationAnswer(type="hallucination", sentence_indexes=indexes),
    )
    assert graded.correct is correct
    assert graded.result.errors == []
    assert graded.result.false_alarms == indexes
    assert graded.feedback_text
