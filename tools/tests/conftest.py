from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
import yaml

type Tree = dict[str, Any]


def option(option_id: str) -> dict[str, str]:
    return {"id": option_id, "text": option_id.upper()}


def valid_tree() -> Tree:
    """A small but complete content tree: one unit, one lesson with one exercise of every type."""
    return {
        "units/u9/unit.yaml": {
            "id": "u9",
            "order": 1,
            "title": "テスト",
            "description": "テスト用のユニット",
            "level": 1,
        },
        "units/u9/u9-l1.yaml": {
            "lesson": {
                "id": "u9-l1",
                "unitId": "u9",
                "order": 1,
                "title": "レッスン",
                "exerciseIds": ["u9-l1-q1", "u9-l1-q2", "u9-l1-q3", "u9-l1-q4", "u9-l1-q5"],
                "intro": {"text": "はじめよう"},
            },
            "exercises": [
                {
                    "id": "u9-l1-q1",
                    "lessonId": "u9-l1",
                    "type": "choice",
                    "question": "どれ？",
                    "options": [{"id": "a", "text": "予測"}, {"id": "b", "text": "検索"}],
                },
                {
                    "id": "u9-l1-q2",
                    "lessonId": "u9-l1",
                    "type": "order",
                    "question": "ならべよう",
                    "items": [{"id": "x", "text": "1"}, {"id": "y", "text": "2"}],
                },
                {
                    "id": "u9-l1-q3",
                    "lessonId": "u9-l1",
                    "type": "fill_blank",
                    "question": "うめよう",
                    "template": "{{p}}と{{q}}",
                    "blanks": [
                        {"id": "p", "options": [option("a"), option("b")]},
                        {"id": "q", "options": [option("c"), option("d")]},
                    ],
                },
                {
                    "id": "u9-l1-q4",
                    "lessonId": "u9-l1",
                    "type": "hallucination",
                    "question": "まちがいをタップ",
                    "topic": "光合成",
                    "sentences": [
                        {"index": 0, "text": "光合成は植物のしくみです。"},
                        {"index": 1, "text": "光合成は根で行われます。"},
                        {"index": 2, "text": "光が必要です。"},
                    ],
                    "errorCount": 1,
                },
                {
                    "id": "u9-l1-q5",
                    "lessonId": "u9-l1",
                    "type": "prompt",
                    "question": "プロンプトを書こう",
                    "task": "要約をたのむ",
                },
            ],
        },
        "units/u9/u9-l1.answers.yaml": {
            "u9-l1-q1": {"type": "choice", "correctOptionId": "a", "explanation": "予測"},
            "u9-l1-q2": {"type": "order", "correctOrder": ["x", "y"], "explanation": "順番"},
            "u9-l1-q3": {
                "type": "fill_blank",
                "correctOptions": {"p": "a", "q": "d"},
                "explanation": "穴埋め",
            },
            "u9-l1-q4": {
                "type": "hallucination",
                "errors": [{"index": 1, "errorType": "fact", "correction": "葉", "tip": "教科書"}],
            },
            "u9-l1-q5": {"type": "prompt", "gradingNotes": "目的と条件"},
        },
    }


def write_tree(root: Path, tree: Tree) -> Path:
    for relative, data in tree.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        text = data if isinstance(data, str) else yaml.safe_dump(data, allow_unicode=True)
        path.write_text(text, encoding="utf-8")
    return root


@pytest.fixture
def make_content(tmp_path: Path) -> Callable[[Tree], Path]:
    """Write a tree under tmp_path/content and return that directory."""
    return lambda tree: write_tree(tmp_path / "content", tree)
