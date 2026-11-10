"""Cross-file checks on loaded content. Every problem is reported with the file it belongs to."""

from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from app.schemas.content import (
    AnswerKey,
    ChoiceAnswerKey,
    ChoiceExercise,
    Exercise,
    FillBlankAnswerKey,
    FillBlankExercise,
    HallucinationAnswerKey,
    HallucinationExercise,
    OrderAnswerKey,
    OrderExercise,
    StoryAnswerKey,
    StoryExercise,
)

from content_tools.audio_lines import hand_written_audio_paths, read_audio_lines
from content_tools.illustrations import hand_written_image_paths, read_scene_images
from content_tools.loader import (
    ANSWERS_SUFFIX,
    Content,
    Problem,
    answers_path_for,
    folder_of,
    lesson_id_of,
    load_content,
)


@dataclass(frozen=True)
class Report:
    content: Content
    problems: tuple[Problem, ...]

    @property
    def ok(self) -> bool:
        return not self.problems


def validate_content(root: Path) -> Report:
    """Load root/units (and root/audio/lines.yaml, root/images/scenes.yaml) and run every
    check. Cross checks run only on schema-valid content, because they would otherwise repeat
    the schema problems as missing references."""
    loaded = load_content(root)
    _, audio_problems = read_audio_lines(root)
    _, image_problems = read_scene_images(root)
    if loaded.problems or audio_problems or image_problems:
        return Report(loaded.content, (*loaded.problems, *audio_problems, *image_problems))
    return Report(loaded.content, tuple(check_content(loaded.content)))


def check_content(content: Content) -> list[Problem]:
    return [
        *_check_units(content),
        *_check_lessons(content),
        *_check_exercises(content),
        *_check_answer_keys(content),
        *hand_written_audio_paths(content),
        *hand_written_image_paths(content),
    ]


@dataclass(frozen=True)
class _Located[T]:
    path: Path
    item: T


def _index[T](
    items: list[_Located[T]], key_of: Callable[[T], str], kind: str
) -> tuple[dict[str, _Located[T]], list[Problem]]:
    """Map id -> item, reporting duplicates (the first occurrence wins)."""
    index: dict[str, _Located[T]] = {}
    problems: list[Problem] = []
    for located in items:
        key = key_of(located.item)
        if key in index:
            problems.append(
                Problem(located.path, f"duplicate {kind} id {key!r} (also in {index[key].path})")
            )
        else:
            index[key] = located
    return index, problems


def _duplicate_orders(items: list[tuple[Path, int, str]], scope: str) -> list[Problem]:
    counts = Counter(order for _, order, _ in items)
    return [
        Problem(path, f"order {order} of {item_id!r} is used more than once in {scope}")
        for path, order, item_id in items
        if counts[order] > 1
    ]


def _check_units(content: Content) -> list[Problem]:
    _, problems = _index([_Located(u.path, u.unit) for u in content.units], lambda u: u.id, "unit")
    for unit_file in content.units:
        if unit_file.unit.id != folder_of(unit_file.path):
            problems.append(
                Problem(
                    unit_file.path,
                    f"unit id {unit_file.unit.id!r} must match its folder "
                    f"{folder_of(unit_file.path)!r}",
                )
            )
    problems += _duplicate_orders(
        [(u.path, u.unit.order, u.unit.id) for u in content.units], "units"
    )
    return problems


def _check_lessons(content: Content) -> list[Problem]:
    unit_ids = {u.unit.id for u in content.units}
    _, problems = _index(
        [_Located(f.path, f.lesson) for f in content.lessons], lambda lesson: lesson.id, "lesson"
    )
    for lesson_file in content.lessons:
        lesson, path = lesson_file.lesson, lesson_file.path
        if lesson.id != lesson_id_of(path):
            problems.append(
                Problem(path, f"lesson id {lesson.id!r} must match the file name {path.name!r}")
            )
        if lesson.unit_id not in unit_ids:
            problems.append(Problem(path, f"unitId {lesson.unit_id!r} does not exist"))
        elif lesson.unit_id != folder_of(path):
            problems.append(
                Problem(
                    path,
                    f"unitId {lesson.unit_id!r} must match the unit folder {folder_of(path)!r}",
                )
            )
        if not lesson.id.startswith(lesson.unit_id + "-"):
            problems.append(
                Problem(path, f"lesson id {lesson.id!r} must start with {lesson.unit_id + '-'!r}")
            )

    for unit_id in sorted(unit_ids):
        problems += _duplicate_orders(
            [
                (f.path, f.lesson.order, f.lesson.id)
                for f in content.lessons
                if f.lesson.unit_id == unit_id
            ],
            f"unit {unit_id!r}",
        )
    return problems


def _exercise_index(content: Content) -> tuple[dict[str, _Located[Exercise]], list[Problem]]:
    return _index(
        [_Located(f.path, e) for f in content.lessons for e in f.exercises],
        lambda e: e.id,
        "exercise",
    )


def _check_exercises(content: Content) -> list[Problem]:
    exercises, problems = _exercise_index(content)

    for lesson_file in content.lessons:
        lesson = lesson_file.lesson
        for exercise_id in lesson.exercise_ids:
            found = exercises.get(exercise_id)
            if found is None:
                problems.append(
                    Problem(lesson_file.path, f"exerciseIds: {exercise_id!r} does not exist")
                )
            elif found.item.lesson_id != lesson.id:
                problems.append(
                    Problem(
                        lesson_file.path,
                        f"exerciseIds: {exercise_id!r} belongs to lesson "
                        f"{found.item.lesson_id!r}, not {lesson.id!r}",
                    )
                )

    for lesson_file in content.lessons:
        for exercise in lesson_file.exercises:
            path = lesson_file.path
            if exercise.lesson_id != lesson_file.lesson.id:
                problems.append(
                    Problem(
                        path,
                        f"exercise {exercise.id!r} has lessonId {exercise.lesson_id!r} but is "
                        f"defined in lesson {lesson_file.lesson.id!r}",
                    )
                )
            elif exercise.id not in lesson_file.lesson.exercise_ids:
                problems.append(
                    Problem(
                        path,
                        f"exercise {exercise.id!r} is not listed in exerciseIds of "
                        f"{exercise.lesson_id!r}",
                    )
                )
            if not exercise.id.startswith(exercise.lesson_id + "-"):
                problems.append(
                    Problem(
                        path,
                        f"exercise id {exercise.id!r} must start with {exercise.lesson_id + '-'!r}",
                    )
                )
    return problems


def _check_answer_keys(content: Content) -> list[Problem]:
    exercises, _ = _exercise_index(content)
    lesson_ids = {f.lesson.id for f in content.lessons}
    keys, problems = _index(
        [_Located(f.path, pair) for f in content.answers for pair in f.keys.items()],
        lambda pair: pair[0],
        "answer key",
    )

    for answers_file in content.answers:
        lesson_id = lesson_id_of(answers_file.path)
        if lesson_id not in lesson_ids:
            problems.append(
                Problem(answers_file.path, f"no lesson {lesson_id!r} for this answers file")
            )
        for exercise_id in answers_file.keys:
            exercise = exercises.get(exercise_id)
            if exercise is None:
                problems.append(
                    Problem(answers_file.path, f"answer key for unknown exercise {exercise_id!r}")
                )
            elif exercise.item.lesson_id != lesson_id:
                problems.append(
                    Problem(
                        answers_file.path,
                        f"answer key {exercise_id!r} belongs in "
                        f"{exercise.item.lesson_id}{ANSWERS_SUFFIX}",
                    )
                )

    for exercise_id, located in exercises.items():
        found = keys.get(exercise_id)
        if found is None:
            problems.append(
                Problem(answers_path_for(located.path), f"missing answer key for {exercise_id!r}")
            )
            continue
        _, key = found.item
        problems += [
            Problem(found.path, f"{exercise_id}: {message}")
            for message in key_mismatches(located.item, key)
        ]
    return problems


def key_mismatches(exercise: Exercise, key: AnswerKey) -> list[str]:
    """Problems between an exercise and its answer key (empty when they agree)."""
    if exercise.type != key.type:
        return [f"answer key type {key.type!r} does not match exercise type {exercise.type!r}"]
    match exercise, key:
        case ChoiceExercise(), ChoiceAnswerKey():
            option_ids = [o.id for o in exercise.options]
            if key.correct_option_id not in option_ids:
                return [f"correctOptionId {key.correct_option_id!r} is not one of {option_ids}"]
        case OrderExercise(), OrderAnswerKey():
            item_ids = [i.id for i in exercise.items]
            if Counter(key.correct_order) != Counter(item_ids):
                return [f"correctOrder {key.correct_order} is not a permutation of {item_ids}"]
        case FillBlankExercise(), FillBlankAnswerKey():
            return _fill_blank_mismatches(exercise, key)
        case HallucinationExercise(), HallucinationAnswerKey():
            return _hallucination_mismatches(exercise, key)
        case StoryExercise(), StoryAnswerKey():
            return _story_mismatches(exercise, key)
    return []


def _fill_blank_mismatches(exercise: FillBlankExercise, key: FillBlankAnswerKey) -> list[str]:
    blanks = {b.id: [o.id for o in b.options] for b in exercise.blanks}
    if set(key.correct_options) != set(blanks):
        return [
            f"correctOptions keys {sorted(key.correct_options)} must equal the blank ids "
            f"{sorted(blanks)}"
        ]
    return [
        f"correctOptions.{blank_id}: {option_id!r} is not one of {blanks[blank_id]}"
        for blank_id, option_id in key.correct_options.items()
        if option_id not in blanks[blank_id]
    ]


def _hallucination_mismatches(
    exercise: HallucinationExercise, key: HallucinationAnswerKey
) -> list[str]:
    problems = [
        f"errors: index {error.index} is out of range (0..{len(exercise.sentences) - 1})"
        for error in key.errors
        if error.index >= len(exercise.sentences)
    ]
    if len(key.errors) != exercise.error_count:
        problems.append(
            f"errors has {len(key.errors)} entries but errorCount is {exercise.error_count}"
        )
    return problems


def _story_mismatches(exercise: StoryExercise, key: StoryAnswerKey) -> list[str]:
    option_ids = [o.id for o in exercise.options]
    problems: list[str] = []
    if key.best_option_id not in option_ids:
        problems.append(f"bestOptionId {key.best_option_id!r} is not one of {option_ids}")
    outcome_ids = [outcome.option_id for outcome in key.outcomes]
    if sorted(outcome_ids) != sorted(option_ids):
        problems.append(
            f"outcomes {sorted(outcome_ids)} must have exactly one entry per option "
            f"{sorted(option_ids)}"
        )
    return problems
