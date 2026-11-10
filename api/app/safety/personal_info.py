"""Find personal information in what a learner typed (requirements §11).

This is a heuristic that turns a mistake into a teaching moment, not a guarantee. Text is
normalized with NFKC first, so full-width input such as "０９０－１２３４－５６７８" or
"名前：" matches the same patterns as half-width input.
"""

import re
import unicodedata
from typing import Literal

PersonalInfoKind = Literal["email", "phone", "postal_code", "address", "name"]

_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")

# A run of digits joined by phone-number separators. Learners also type the long vowel mark
# "ー" or a dash instead of a hyphen. Whether a run is a phone number is decided in _is_phone.
_DIGIT_RUN = re.compile(r"\(?\+?\d(?:[-‐−–—ー.()\s]{0,2}\d)*")
_DIGIT_GROUP = re.compile(r"\d+")

# 〒123-4567 or 123-4567 (but not the middle of 090-1234-5678).
_POSTAL_CODE = re.compile(r"〒\s*\d{3}-?\d{4}|(?<![\d-])\d{3}-\d{4}(?![\d-])")

_ADDRESS = re.compile(
    r"\d+\s*丁目"
    r"|\d+\s*番地"
    r"|\d+\s*番\s*\d+\s*号"
    # A place name in kanji followed by a block number: 渋谷区神南1-2-3, 北区梅田1-1.
    r"|[都道府県市区町村][一-鿿々ヶ]{0,8}\d{1,4}-\d{1,4}"
)

# Introducing oneself by name, or filling in a name field. Mentions such as "名前は書かないで"
# are not matched, so a learner who writes a privacy rule is not blocked.
_NAME = re.compile(
    r"(?:私|わたし|僕|ぼく|俺|おれ|自分|うち)の(?:名前|なまえ|氏名|フルネーム)は"
    r"|(?:名前|なまえ|氏名|本名|フルネーム)\s*[:=]\s*\S"
)


def find_personal_info(text: str) -> list[PersonalInfoKind]:
    """The kinds of personal information text seems to contain, in a fixed order."""
    normalized = unicodedata.normalize("NFKC", text)
    checks: list[tuple[PersonalInfoKind, bool]] = [
        ("email", _EMAIL.search(normalized) is not None),
        ("phone", any(_is_phone(run.group()) for run in _DIGIT_RUN.finditer(normalized))),
        ("postal_code", _POSTAL_CODE.search(normalized) is not None),
        ("address", _ADDRESS.search(normalized) is not None),
        ("name", _NAME.search(normalized) is not None),
    ]
    return [kind for kind, found in checks if found]


def _is_phone(run: str) -> bool:
    """Whether consecutive digit groups of the run spell a Japanese phone number.

    Looking at consecutive groups (not the whole run) still finds "090-1234-5678" when other
    numbers follow it, as in "090-1234-5678 2026".
    """
    groups = _DIGIT_GROUP.findall(run)
    if run.lstrip("(").startswith("+") and groups[0] == "81":
        groups[0] = "0"  # +81-90-... is 090-...
    for start in range(len(groups)):
        digits = ""
        for group in groups[start:]:
            digits += group
            if digits.startswith("0") and len(digits) in (10, 11):
                return True
            if len(digits) > 11:
                break
    return False
