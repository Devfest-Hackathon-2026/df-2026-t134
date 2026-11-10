"""Deterministic grading of answers (pure functions).

``answer_problem`` checks a submitted answer against the public exercise (the 400 cases);
``grade`` compares an answer that passed that check with the answer key.
"""

from dataclasses import dataclass

from app.schemas.answers import (
    Answer,
    AnswerResult,
    ChoiceAnswer,
    ChoiceResult,
    FillBlankAnswer,
    FillBlankResult,
    HallucinationAnswer,
    HallucinationResult,
    LiveCheckAnswer,
    LiveCheckResult,
    OrderAnswer,
    OrderResult,
    StoryAnswer,
    StoryResult,
)
from app.schemas.content import (
    AnswerKey,
    ChoiceAnswerKey,
    ChoiceExercise,
    Exercise,
    FillBlankAnswerKey,
    FillBlankExercise,
    HallucinationAnswerKey,
    HallucinationExercise,
    LiveCheckExercise,
    OrderAnswerKey,
    OrderExercise,
    PromptExercise,
    StoryAnswerKey,
    StoryExercise,
)
from app.schemas.firestore import LiveCheckSession


@dataclass(frozen=True, slots=True)
class Graded:
    correct: bool
    result: AnswerResult
    # Stored as Attempt.feedback_text (and read aloud by the TTS endpoint later).
    feedback_text: str


def answer_problem(exercise: Exercise, answer: Answer) -> str | None:
    """Why the answer cannot be graded for this exercise, or None when it can."""
    match exercise, answer:
        case PromptExercise(), _:
            return "prompt exercises are graded by /v1/prompt/evaluate"
        case ChoiceExercise(), ChoiceAnswer():
            if answer.option_id not in {option.id for option in exercise.options}:
                return "optionId is not an option of this exercise"
        case OrderExercise(), OrderAnswer():
            # The request model already guarantees unique ids.
            if sorted(answer.item_ids) != sorted(item.id for item in exercise.items):
                return "itemIds must be an ordering of every item of this exercise"
        case FillBlankExercise(), FillBlankAnswer():
            blanks = {
                blank.id: {option.id for option in blank.options} for blank in exercise.blanks
            }
            if answer.selected_options.keys() != blanks.keys():
                return "selectedOptions must have exactly one entry per blank"
            if any(option not in blanks[b] for b, option in answer.selected_options.items()):
                return "selectedOptions contains an option that is not in its blank"
        case HallucinationExercise(), HallucinationAnswer():
            if any(index >= len(exercise.sentences) for index in answer.sentence_indexes):
                return "sentenceIndexes contains an index outside the sentences"
        case LiveCheckExercise(), LiveCheckAnswer():
            pass  # the sentences are in the session, checked by grade_live_check's caller

        case StoryExercise(), StoryAnswer():
            if answer.option_id not in {option.id for option in exercise.options}:
                return "optionId is not an option of this exercise"
        case _:
            return f"answer type {answer.type} does not match exercise type {exercise.type}"
    return None


def grade_choice(key: ChoiceAnswerKey, answer: ChoiceAnswer) -> Graded:
    result = ChoiceResult(
        type="choice", correct_option_id=key.correct_option_id, explanation=key.explanation
    )
    return Graded(answer.option_id == key.correct_option_id, result, key.explanation)


def grade_order(key: OrderAnswerKey, answer: OrderAnswer) -> Graded:
    result = OrderResult(type="order", correct_order=key.correct_order, explanation=key.explanation)
    return Graded(answer.item_ids == key.correct_order, result, key.explanation)


def grade_fill_blank(key: FillBlankAnswerKey, answer: FillBlankAnswer) -> Graded:
    result = FillBlankResult(
        type="fill_blank", correct_options=key.correct_options, explanation=key.explanation
    )
    return Graded(answer.selected_options == key.correct_options, result, key.explanation)


def grade_hallucination(key: HallucinationAnswerKey, answer: HallucinationAnswer) -> Graded:
    """Compare marked claims, including an explicit empty answer for a clean response."""
    errors = sorted(key.errors, key=lambda error: error.index)
    wrong = {error.index for error in errors}
    tapped = set(answer.sentence_indexes)
    result = HallucinationResult(
        type="hallucination",
        errors=errors,
        found=sorted(tapped & wrong),
        missed=sorted(wrong - tapped),
        false_alarms=sorted(tapped - wrong),
    )
    feedback = "\n".join(line for error in errors for line in (error.correction, error.tip))
    if not errors:
        feedback = (
            "この回答には誤りがありません。出典と照らし合わせて確かめられたね。"
            if not result.false_alarms
            else "この回答には誤りがありません。選んだ部分も出典と照らし合わせよう。"
        )
    return Graded(not result.missed and not result.false_alarms, result, feedback)


def grade_live_check(session: LiveCheckSession, answer: LiveCheckAnswer) -> Graded:
    """Like hallucination, against the errors put into this session, with every source."""
    graded = grade_hallucination(
        HallucinationAnswerKey(type="hallucination", errors=session.errors),
        HallucinationAnswer(type="hallucination", sentence_indexes=answer.sentence_indexes),
    )
    found = graded.result
    assert isinstance(found, HallucinationResult)
    ordered = sorted(session.sources.items(), key=lambda item: int(item[0]))
    sources = list(dict.fromkeys(source for _, sources in ordered for source in sources))
    result = LiveCheckResult(
        type="live_check",
        errors=found.errors,
        found=found.found,
        missed=found.missed,
        false_alarms=found.false_alarms,
        sources=sources,
    )
    return Graded(graded.correct, result, graded.feedback_text)


def grade_story(key: StoryAnswerKey, answer: StoryAnswer) -> Graded:
    """Correct when the learner picked the best option; the result plays what happens next."""
    outcome = next((o for o in key.outcomes if o.option_id == answer.option_id), None)
    if outcome is None:
        # validate.py requires an outcome for every option, so this is corrupt content.
        raise ValueError(f"story answer key has no outcome for option {answer.option_id}")
    result = StoryResult(
        type="story",
        best_option_id=key.best_option_id,
        outcome=outcome.scenes,
        explanation=key.explanation,
    )
    feedback = "\n".join([*(scene.text for scene in outcome.scenes), key.explanation])
    return Graded(answer.option_id == key.best_option_id, result, feedback)


def grade(key: AnswerKey, answer: Answer) -> Graded:
    """Grade an answer that passed answer_problem. A key of another type is corrupt content."""
    match key, answer:
        case ChoiceAnswerKey(), ChoiceAnswer():
            return grade_choice(key, answer)
        case OrderAnswerKey(), OrderAnswer():
            return grade_order(key, answer)
        case FillBlankAnswerKey(), FillBlankAnswer():
            return grade_fill_blank(key, answer)
        case HallucinationAnswerKey(), HallucinationAnswer():
            return grade_hallucination(key, answer)
        case StoryAnswerKey(), StoryAnswer():
            return grade_story(key, answer)
        case _:
            raise ValueError(f"answer key type {key.type} does not match answer type {answer.type}")
