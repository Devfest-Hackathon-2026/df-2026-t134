import copy
from collections.abc import Callable
from pathlib import Path

import pytest

from content_tools.validate import validate_content
from tests.conftest import Tree, valid_tree

UNIT = "units/u9/unit.yaml"
LESSON = "units/u9/u9-l1.yaml"
ANSWERS = "units/u9/u9-l1.answers.yaml"

type MakeContent = Callable[[Tree], Path]


def problems_for(make_content: MakeContent, tree: Tree) -> list[str]:
    root = make_content(tree)
    return [f"{p.path.relative_to(root)}: {p.message}" for p in validate_content(root).problems]


def exercise(tree: Tree, index: int) -> dict:
    return tree[LESSON]["exercises"][index]


def second_lesson(tree: Tree) -> None:
    """Add lesson u9-l2 with a single choice exercise and its key."""
    lesson = copy.deepcopy(tree[LESSON])
    lesson["lesson"] |= {"id": "u9-l2", "order": 2, "exerciseIds": ["u9-l2-q1"]}
    lesson["exercises"] = [exercise(tree, 0) | {"id": "u9-l2-q1", "lessonId": "u9-l2"}]
    tree["units/u9/u9-l2.yaml"] = lesson
    tree["units/u9/u9-l2.answers.yaml"] = {"u9-l2-q1": tree[ANSWERS]["u9-l1-q1"]}


def test_valid_tree_has_no_problems(make_content: MakeContent) -> None:
    report = validate_content(make_content(valid_tree()))

    assert report.problems == ()
    assert [len(f.exercises) for f in report.content.lessons] == [5]


# ---- file level ---------------------------------------------------------------------------


def test_missing_units_directory(tmp_path: Path) -> None:
    problems = validate_content(tmp_path).problems

    assert [p.message for p in problems] == ["directory not found"]


def test_schema_errors_are_reported_with_location(make_content: MakeContent) -> None:
    tree = valid_tree()
    exercise(tree, 0)["options"] = [{"id": "a", "text": "only one"}]
    tree[UNIT]["level"] = 9

    problems = problems_for(make_content, tree)

    assert any(p.startswith(f"{UNIT}: level:") for p in problems)
    assert any(p.startswith(f"{LESSON}: exercises.0.choice.options:") for p in problems)


def test_duplicate_yaml_keys_are_rejected(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[ANSWERS] = (
        "u9-l1-q1: {type: choice, correctOptionId: a, explanation: x}\n"
        "u9-l1-q1: {type: choice, correctOptionId: b, explanation: y}\n"
    )

    [problem] = problems_for(make_content, tree)

    assert problem.startswith(f"{ANSWERS}: invalid YAML") and "duplicate key" in problem


@pytest.mark.parametrize(
    ("relative", "content", "expected"),
    [
        ("units/u9/notes.txt", "x", "units/u9/notes.txt: unexpected entry"),
        ("units/u9/u9-l2.yml", "x", "units/u9/u9-l2.yml: unexpected entry"),
        ("units/readme.yaml", "x", "units/readme.yaml: unexpected file"),
        ("units/u8/u8-l1.answers.yaml", "{}", "units/u8/unit.yaml: missing unit file"),
        ("units/u9/u9-l9.yaml", "", "units/u9/u9-l9.yaml: file is empty"),
    ],
)
def test_unexpected_or_empty_files(
    make_content: MakeContent, relative: str, content: str, expected: str
) -> None:
    tree = valid_tree() | {relative: content}

    [problem] = problems_for(make_content, tree)

    assert problem.startswith(expected)


# ---- units and lessons --------------------------------------------------------------------


def test_unit_id_must_match_folder(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree["units/u8/unit.yaml"] = tree[UNIT] | {"order": 2}

    problems = problems_for(make_content, tree)

    assert any("duplicate unit id 'u9'" in p for p in problems)
    assert any(p.startswith("units/u8/unit.yaml: unit id 'u9' must match") for p in problems)


def test_unit_orders_must_be_unique(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree["units/u8/unit.yaml"] = tree[UNIT] | {"id": "u8"}

    problems = problems_for(make_content, tree)

    assert sum("order 1" in p and "units" in p for p in problems) == 2


def test_lesson_orders_must_be_unique_within_unit(make_content: MakeContent) -> None:
    tree = valid_tree()
    second_lesson(tree)
    tree["units/u9/u9-l2.yaml"]["lesson"]["order"] = 1

    problems = problems_for(make_content, tree)

    assert sorted(p.split(":")[0] for p in problems) == [LESSON, "units/u9/u9-l2.yaml"]
    assert all("used more than once in unit 'u9'" in p for p in problems)


def test_lesson_unit_must_exist(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[LESSON]["lesson"]["unitId"] = "u7"

    problems = problems_for(make_content, tree)

    assert f"{LESSON}: unitId 'u7' does not exist" in problems


def test_lesson_unit_must_match_folder(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree["units/u8/unit.yaml"] = tree[UNIT] | {"id": "u8", "order": 2}
    tree[LESSON]["lesson"]["unitId"] = "u8"

    problems = problems_for(make_content, tree)

    assert f"{LESSON}: unitId 'u8' must match the unit folder 'u9'" in problems


def test_lesson_id_must_match_file_name(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree["units/u9/u9-l5.yaml"] = tree.pop(LESSON)
    tree["units/u9/u9-l5.answers.yaml"] = tree.pop(ANSWERS)

    problems = problems_for(make_content, tree)

    assert "units/u9/u9-l5.yaml: lesson id 'u9-l1' must match the file name 'u9-l5.yaml'" in (
        problems
    )
    assert "units/u9/u9-l5.answers.yaml: no lesson 'u9-l5' for this answers file" in problems


def test_duplicate_lesson_and_exercise_ids(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree["units/u9/u9-l2.yaml"] = copy.deepcopy(tree[LESSON])
    tree["units/u9/u9-l2.yaml"]["lesson"]["order"] = 2

    problems = problems_for(make_content, tree)

    assert any("duplicate lesson id 'u9-l1'" in p for p in problems)
    assert any("duplicate exercise id 'u9-l1-q1'" in p for p in problems)


# ---- exercises ----------------------------------------------------------------------------


def test_lesson_references_unknown_exercise(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[LESSON]["lesson"]["exerciseIds"].append("u9-l1-q9")

    problems = problems_for(make_content, tree)

    assert problems == [f"{LESSON}: exerciseIds: 'u9-l1-q9' does not exist"]


def test_exercise_not_listed_in_its_lesson(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[LESSON]["lesson"]["exerciseIds"].remove("u9-l1-q5")

    problems = problems_for(make_content, tree)

    assert problems == [f"{LESSON}: exercise 'u9-l1-q5' is not listed in exerciseIds of 'u9-l1'"]


def test_exercise_lesson_id_must_be_its_lesson(make_content: MakeContent) -> None:
    tree = valid_tree()
    second_lesson(tree)
    # u9-l1 lists an exercise that is defined (and owned) by u9-l2.
    tree[LESSON]["lesson"]["exerciseIds"].append("u9-l2-q1")
    exercise(tree, 4)["lessonId"] = "u9-l2"

    problems = problems_for(make_content, tree)

    assert f"{LESSON}: exerciseIds: 'u9-l2-q1' belongs to lesson 'u9-l2', not 'u9-l1'" in problems
    assert (
        f"{LESSON}: exercise 'u9-l1-q5' has lessonId 'u9-l2' but is defined in lesson 'u9-l1'"
        in problems
    )


def test_exercise_id_must_start_with_lesson_id(make_content: MakeContent) -> None:
    tree = valid_tree()
    exercise(tree, 0)["id"] = "q1"
    tree[LESSON]["lesson"]["exerciseIds"][0] = "q1"
    tree[ANSWERS]["q1"] = tree[ANSWERS].pop("u9-l1-q1")

    problems = problems_for(make_content, tree)

    assert problems == [f"{LESSON}: exercise id 'q1' must start with 'u9-l1-'"]


# ---- answer keys --------------------------------------------------------------------------


def test_missing_answer_key(make_content: MakeContent) -> None:
    tree = valid_tree()
    del tree[ANSWERS]["u9-l1-q2"]

    assert problems_for(make_content, tree) == [f"{ANSWERS}: missing answer key for 'u9-l1-q2'"]


def test_missing_answers_file(make_content: MakeContent) -> None:
    tree = valid_tree()
    del tree[ANSWERS]

    problems = problems_for(make_content, tree)

    assert len(problems) == 5
    assert all(p.startswith(f"{ANSWERS}: missing answer key") for p in problems)


def test_orphan_answer_key(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[ANSWERS]["u9-l1-q9"] = tree[ANSWERS]["u9-l1-q1"]

    assert problems_for(make_content, tree) == [
        f"{ANSWERS}: answer key for unknown exercise 'u9-l1-q9'"
    ]


def test_answer_key_in_the_wrong_answers_file(make_content: MakeContent) -> None:
    tree = valid_tree()
    second_lesson(tree)
    tree[ANSWERS]["u9-l2-q1"] = tree["units/u9/u9-l2.answers.yaml"].pop("u9-l2-q1")

    problems = problems_for(make_content, tree)

    assert problems == [f"{ANSWERS}: answer key 'u9-l2-q1' belongs in u9-l2.answers.yaml"]


def test_duplicate_answer_key_across_files(make_content: MakeContent) -> None:
    tree = valid_tree()
    second_lesson(tree)
    tree["units/u9/u9-l2.answers.yaml"]["u9-l1-q1"] = tree[ANSWERS]["u9-l1-q1"]

    problems = problems_for(make_content, tree)

    assert any("duplicate answer key id 'u9-l1-q1'" in p for p in problems)


def test_answer_key_type_must_match(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[ANSWERS]["u9-l1-q1"] = tree[ANSWERS]["u9-l1-q5"]

    assert problems_for(make_content, tree) == [
        f"{ANSWERS}: u9-l1-q1: answer key type 'prompt' does not match exercise type 'choice'"
    ]


@pytest.mark.parametrize(
    ("exercise_id", "key_patch", "expected"),
    [
        ("u9-l1-q1", {"correctOptionId": "z"}, "correctOptionId 'z' is not one of ['a', 'b']"),
        ("u9-l1-q2", {"correctOrder": ["x", "x"]}, "is not a permutation of ['x', 'y']"),
        ("u9-l1-q2", {"correctOrder": ["x", "y", "z"]}, "is not a permutation"),
        ("u9-l1-q3", {"correctOptions": {"p": "a"}}, "must equal the blank ids ['p', 'q']"),
        (
            "u9-l1-q3",
            {"correctOptions": {"p": "a", "r": "c"}},
            "must equal the blank ids ['p', 'q']",
        ),
        (
            "u9-l1-q3",
            {"correctOptions": {"p": "a", "q": "a"}},
            "correctOptions.q: 'a' is not one of ['c', 'd']",
        ),
        (
            "u9-l1-q4",
            {"errors": [{"index": 3, "errorType": "fact", "correction": "c", "tip": "t"}]},
            "index 3 is out of range (0..2)",
        ),
        (
            "u9-l1-q4",
            {
                "errors": [
                    {"index": 0, "errorType": "fact", "correction": "c", "tip": "t"},
                    {"index": 1, "errorType": "number", "correction": "c", "tip": "t"},
                ]
            },
            "errors has 2 entries but errorCount is 1",
        ),
    ],
)
def test_answer_key_must_fit_its_exercise(
    make_content: MakeContent, exercise_id: str, key_patch: dict, expected: str
) -> None:
    tree = valid_tree()
    tree[ANSWERS][exercise_id] |= key_patch

    [problem] = problems_for(make_content, tree)

    assert problem.startswith(f"{ANSWERS}: {exercise_id}: ")
    assert expected in problem


def test_every_problem_is_reported_at_once(make_content: MakeContent) -> None:
    tree = valid_tree()
    tree[ANSWERS]["u9-l1-q1"]["correctOptionId"] = "z"
    del tree[ANSWERS]["u9-l1-q2"]
    tree[LESSON]["lesson"]["exerciseIds"].append("u9-l1-q9")

    assert len(problems_for(make_content, tree)) == 3
