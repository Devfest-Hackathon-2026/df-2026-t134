"""Contracts of the agent builder exercise (F-12)."""

import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas.answers import AgentStep, SubmitAnswerRequest
from app.schemas.content import AnswerKey, Exercise

exercise = TypeAdapter(Exercise)
answer_key = TypeAdapter(AnswerKey)

AGENT = {
    "id": "u4-l1-q1",
    "lessonId": "u4-l1",
    "type": "agent",
    "question": "エージェントに道具とルールを持たせよう",
    "goal": "明日の遠足の持ち物リストを作る",
    "situation": "明日は高尾山へ遠足。天気によって持ち物が変わる。",
    "tools": [
        {"id": "weather", "name": "天気を調べる", "description": "明日の天気予報を調べる"},
        {"id": "memo", "name": "メモに書く", "description": "リストをメモに残す"},
        {"id": "calc", "name": "計算する", "description": "数字を計算する"},
    ],
    "rules": [{"id": "ask", "name": "人に聞く", "description": "分からないときは先生に聞く"}],
    "maxTools": 2,
}

KEY = {
    "type": "agent",
    "requiredToolIds": ["weather", "memo"],
    "requiredRuleIds": ["ask"],
    "toolOutputs": {"weather": "明日は午後から雨。", "memo": "メモに保存しました。"},
    "explanation": "天気が分からないと、雨具が必要か決められないね。",
}


def test_agent_exercise_and_key_parse() -> None:
    parsed = exercise.validate_python(AGENT)
    key = answer_key.validate_python(KEY)

    assert parsed.max_tools == 2
    assert key.forbidden_tool_ids == []


@pytest.mark.parametrize(
    "overrides",
    [
        {"maxTools": 4},
        {"rules": [{"id": "memo", "name": "x", "description": "y"}]},
        {"tools": [{"id": "weather", "name": "x", "description": "y"}]},
    ],
)
def test_invalid_agent_exercises_are_rejected(overrides: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        exercise.validate_python(AGENT | overrides)


def test_agent_key_is_consistent() -> None:
    with pytest.raises(ValidationError, match="both required and forbidden"):
        answer_key.validate_python(KEY | {"forbiddenToolIds": ["weather"]})
    with pytest.raises(ValidationError, match="needs an output"):
        answer_key.validate_python(KEY | {"toolOutputs": {"weather": "雨"}})


def test_agent_answer_needs_unique_blocks() -> None:
    answer = {"type": "agent", "toolIds": ["weather", "memo"], "ruleIds": ["ask"]}
    SubmitAnswerRequest.model_validate({"exerciseId": "u4-l1-q1", "answer": answer})

    with pytest.raises(ValidationError):
        SubmitAnswerRequest.model_validate(
            {"exerciseId": "u4-l1-q1", "answer": answer | {"toolIds": ["memo", "memo"]}}
        )


def test_steps_carry_a_tool_id_exactly_when_a_tool_is_involved() -> None:
    AgentStep.model_validate({"kind": "tool", "text": "天気を調べる", "toolId": "weather"})
    AgentStep.model_validate({"kind": "think", "text": "まず天気を確かめよう"})

    with pytest.raises(ValidationError):
        AgentStep.model_validate({"kind": "tool", "text": "x"})
    with pytest.raises(ValidationError):
        AgentStep.model_validate({"kind": "answer", "text": "x", "toolId": "memo"})
