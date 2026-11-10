import 'package:ailearn/features/lesson/personal_info_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cases shared with api/tests/test_personal_info.py for the kinds the app
/// checks, so the warning matches what the server blocks.
void main() {
  for (final (text, kind) in [
    ('連絡は taro.yamada+school@example.co.jp にください', PersonalInfoKind.email),
    ('ｔａｒｏ＠ｅｘａｍｐｌｅ．ｃｏｍ に送って', PersonalInfoKind.email),
    ('電話は090-1234-5678です', PersonalInfoKind.phone),
    ('０９０－１２３４－５６７８にかけて', PersonalInfoKind.phone),
    ('09012345678', PersonalInfoKind.phone),
    ('090ー1234ー5678', PersonalInfoKind.phone),
    ('家の電話 03-1234-5678', PersonalInfoKind.phone),
    ('(03)1234-5678', PersonalInfoKind.phone),
    ('+81 90 1234 5678', PersonalInfoKind.phone),
    ('090-1234-5678 2026年', PersonalInfoKind.phone),
    ('〒150-0041', PersonalInfoKind.postalCode),
    ('郵便番号は150-0041です', PersonalInfoKind.postalCode),
    ('郵便番号は１５０－００４１', PersonalInfoKind.postalCode),
  ]) {
    test('finds ${kind.name} in "$text"', () {
      expect(findPersonalInfo(text), contains(kind));
    });
  }

  for (final text in [
    '文化祭の出し物のアイデアを10個、予算3万円以内、表で出して',
    '2026-11-09 の予定を 3 つの箇条書きでまとめて',
    '1234567890 を 2 倍にして',
    '手順1-2の説明を200字で',
    '市販のお菓子を1-2個使うレシピ',
    '名前は書かないで、個人情報は入れないでください',
    '富士山の高さは3776メートル',
    '電話番号のような個人情報は入れないで',
    '',
  ]) {
    test('does not flag "$text"', () {
      expect(findPersonalInfo(text), isEmpty);
    });
  }

  test('reports every kind once in a fixed order', () {
    expect(findPersonalInfo('a@example.com 〒150-0041 090-1234-5678 b@x.jp'), [
      PersonalInfoKind.email,
      PersonalInfoKind.phone,
      PersonalInfoKind.postalCode,
    ]);
  });
}
