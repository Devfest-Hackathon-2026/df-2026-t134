"""Every scene of the story exercises: the scenes of the exercises (public) and the outcome
scenes of their answer keys (server only). Shared by the illustration and the voice tools."""

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from app.schemas.content import Scene, StoryAnswerKey, StoryExercise

from content_tools.loader import AnswersFile, Content, LessonFile


@dataclass(frozen=True)
class LocatedScene:
    path: Path  # the lesson or answers file it comes from
    where: str  # e.g. "exercise u1-l4-q1 scenes[0]" or "u1-l4-q1 outcome b scenes[1]"
    scene: Scene


def all_scenes(content: Content) -> list[LocatedScene]:
    """Every story scene, in file order: a lesson's exercises, then its answer keys."""
    scenes: list[LocatedScene] = []
    for file in content.lessons:
        for exercise in file.exercises:
            if isinstance(exercise, StoryExercise):
                scenes += [
                    LocatedScene(file.path, f"exercise {exercise.id} scenes[{i}]", scene)
                    for i, scene in enumerate(exercise.scenes)
                ]
    for answers in content.answers:
        for exercise_id, key in answers.keys.items():
            if isinstance(key, StoryAnswerKey):
                scenes += [
                    LocatedScene(
                        answers.path,
                        f"{exercise_id} outcome {outcome.option_id} scenes[{i}]",
                        scene,
                    )
                    for outcome in key.outcomes
                    for i, scene in enumerate(outcome.scenes)
                ]
    return scenes


def map_scenes(content: Content, update: Callable[[Scene], Scene]) -> Content:
    """Content with every story scene replaced by update(scene)."""

    def lesson_file(file: LessonFile) -> LessonFile:
        exercises = tuple(
            exercise.model_copy(update={"scenes": [update(s) for s in exercise.scenes]})
            if isinstance(exercise, StoryExercise)
            else exercise
            for exercise in file.exercises
        )
        return LessonFile(file.path, file.lesson, exercises)

    def answers_file(file: AnswersFile) -> AnswersFile:
        keys = {
            exercise_id: key.model_copy(
                update={
                    "outcomes": [
                        outcome.model_copy(update={"scenes": [update(s) for s in outcome.scenes]})
                        for outcome in key.outcomes
                    ]
                }
            )
            if isinstance(key, StoryAnswerKey)
            else key
            for exercise_id, key in file.keys.items()
        }
        return AnswersFile(file.path, keys)

    return Content(
        content.units,
        tuple(lesson_file(f) for f in content.lessons),
        tuple(answers_file(f) for f in content.answers),
    )
