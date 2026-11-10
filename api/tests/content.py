"""Small teaching material for the API tests: one lesson with one exercise per graded type,
and one lesson with a prompt exercise."""

from typing import Any

from pydantic import TypeAdapter

from app.repo.memory import InMemoryLearningRepo
from app.schemas.content import AnswerKey, Exercise, Lesson

LESSON_ID = "t1-l1"
PROMPT_LESSON_ID = "t1-l2"
CHOICE_ID, ORDER_ID, FILL_ID, HALLUCINATION_ID = (f"{LESSON_ID}-q{n}" for n in range(1, 5))
PROMPT_ID = f"{PROMPT_LESSON_ID}-q1"


def _options(*ids: str) -> list[dict[str, str]]:
    return [{"id": option_id, "text": option_id.upper()} for option_id in ids]


_LESSONS: list[dict[str, Any]] = [
    {
        "id": LESSON_ID,
        "unitId": "t1",
        "order": 1,
        "title": "テスト",
        "exerciseIds": [CHOICE_ID, ORDER_ID, FILL_ID, HALLUCINATION_ID],
    },
    {
        "id": PROMPT_LESSON_ID,
        "unitId": "t1",
        "order": 2,
        "title": "書く",
        "exerciseIds": [PROMPT_ID],
    },
]

_EXERCISES: list[dict[str, Any]] = [
    {
        "id": CHOICE_ID,
        "lessonId": LESSON_ID,
        "type": "choice",
        "question": "どれ？",
        "options": _options("a", "b", "c"),
    },
    {
        "id": ORDER_ID,
        "lessonId": LESSON_ID,
        "type": "order",
        "question": "ならべよう",
        "items": _options("input", "predict", "append"),
    },
    {
        "id": FILL_ID,
        "lessonId": LESSON_ID,
        "type": "fill_blank",
        "question": "うめよう",
        "template": "{{p}}と{{q}}",
        "blanks": [
            {"id": "p", "options": _options("a", "b")},
            {"id": "q", "options": _options("c", "d")},
        ],
    },
    {
        "id": HALLUCINATION_ID,
        "lessonId": LESSON_ID,
        "type": "hallucination",
        "question": "まちがいをタップ",
        "topic": "富士山",
        "sentences": [
            {"index": 0, "text": "富士山は日本でいちばん高い山です。"},
            {"index": 1, "text": "高さは 5776 メートルです。"},
            {"index": 2, "text": "静岡県と山梨県にまたがっています。"},
            {"index": 3, "text": "2013 年に世界自然遺産になりました。"},
        ],
        "errorCount": 2,
    },
    {
        "id": PROMPT_ID,
        "lessonId": PROMPT_LESSON_ID,
        "type": "prompt",
        "question": "プロンプトを書こう",
        "task": "要約をたのむ",
    },
]

_ANSWER_KEYS: dict[str, dict[str, Any]] = {
    CHOICE_ID: {"type": "choice", "correctOptionId": "b", "explanation": "予測だよ。\nb が正解。"},
    ORDER_ID: {
        "type": "order",
        "correctOrder": ["input", "predict", "append"],
        "explanation": "入力→予測→追加",
    },
    FILL_ID: {
        "type": "fill_blank",
        "correctOptions": {"p": "a", "q": "d"},
        "explanation": "a と d",
    },
    HALLUCINATION_ID: {
        "type": "hallucination",
        "errors": [
            {
                "index": 3,
                "errorType": "fact",
                "correction": "文化遺産です。",
                "tip": "種類に注意。",
            },
            {
                "index": 1,
                "errorType": "number",
                "correction": "3776 m です。",
                "tip": "数字を確認。",
            },
        ],
    },
    PROMPT_ID: {"type": "prompt", "gradingNotes": "目的と条件"},
}

# One correct and one wrong answer per graded exercise (request JSON).
CORRECT_ANSWERS: dict[str, dict[str, Any]] = {
    CHOICE_ID: {"type": "choice", "optionId": "b"},
    ORDER_ID: {"type": "order", "itemIds": ["input", "predict", "append"]},
    FILL_ID: {"type": "fill_blank", "selectedOptions": {"p": "a", "q": "d"}},
    HALLUCINATION_ID: {"type": "hallucination", "sentenceIndexes": [3, 1]},
}
WRONG_ANSWERS: dict[str, dict[str, Any]] = {
    CHOICE_ID: {"type": "choice", "optionId": "a"},
    ORDER_ID: {"type": "order", "itemIds": ["predict", "input", "append"]},
    FILL_ID: {"type": "fill_blank", "selectedOptions": {"p": "a", "q": "c"}},
    HALLUCINATION_ID: {"type": "hallucination", "sentenceIndexes": [1]},
}

_exercise = TypeAdapter(Exercise)
_answer_key = TypeAdapter(AnswerKey)

LESSONS = [Lesson.model_validate(data) for data in _LESSONS]
EXERCISES = {data["id"]: _exercise.validate_python(data) for data in _EXERCISES}
ANSWER_KEYS = {
    exercise_id: _answer_key.validate_python(d) for exercise_id, d in _ANSWER_KEYS.items()
}


def make_repo() -> InMemoryLearningRepo:
    return InMemoryLearningRepo(LESSONS, EXERCISES.values(), ANSWER_KEYS)
