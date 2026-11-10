import pytest

from app.safety.personal_info import PersonalInfoKind, find_personal_info


@pytest.mark.parametrize(
    ("text", "kind"),
    [
        ("連絡は taro.yamada+school@example.co.jp にください", "email"),
        ("ｔａｒｏ＠ｅｘａｍｐｌｅ．ｃｏｍ に送って", "email"),
        ("電話は090-1234-5678です", "phone"),
        ("０９０－１２３４－５６７８にかけて", "phone"),
        ("09012345678", "phone"),
        ("090ー1234ー5678", "phone"),
        ("家の電話 03-1234-5678", "phone"),
        ("(03)1234-5678", "phone"),
        ("+81 90 1234 5678", "phone"),
        ("090-1234-5678 2026年", "phone"),
        ("〒150-0041", "postal_code"),
        ("郵便番号は150-0041です", "postal_code"),
        ("東京都渋谷区神南1-2-3に住んでいます", "address"),
        ("名古屋市中村区名駅4丁目", "address"),
        ("さくら町3番地", "address"),
        ("1番2号", "address"),
        ("私の名前は山田太郎です", "name"),
        ("ぼくのなまえは たろう", "name"),
        ("名前：山田太郎", "name"),
        ("氏名=山田花子", "name"),
    ],
)
def test_personal_information_is_found(text: str, kind: PersonalInfoKind) -> None:
    assert kind in find_personal_info(text)


@pytest.mark.parametrize(
    "text",
    [
        "文化祭の出し物のアイデアを10個、予算3万円以内、表で出して",
        "2026-11-09 の予定を 3 つの箇条書きでまとめて",
        "1234567890 を 2 倍にして",
        "手順1-2の説明を200字で",
        "市販のお菓子を1-2個使うレシピ",
        "名前は書かないで、個人情報は入れないでください",
        "フルネームは出さないでね",
        "富士山の高さは3776メートル",
        "電話番号のような個人情報は入れないで",
    ],
)
def test_ordinary_prompts_are_not_flagged(text: str) -> None:
    assert find_personal_info(text) == []


def test_every_kind_found_is_reported_once_in_a_fixed_order() -> None:
    text = "私の名前は山田です。〒150-0041 渋谷区神南1-2-3、090-1234-5678、a@example.com"

    assert find_personal_info(text) == ["email", "phone", "postal_code", "address", "name"]
