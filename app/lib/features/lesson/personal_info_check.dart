/// A warning before a prompt leaves the device when it seems to contain
/// personal information (requirements §11).
///
/// UX only: the server (api/app/safety/personal_info.py) is the authority and
/// blocks more kinds (addresses, names). The patterns follow the server's, so
/// what is flagged here is usually blocked there too.
library;

enum PersonalInfoKind {
  email('メールアドレス'),
  phone('電話番号'),
  postalCode('郵便番号');

  const PersonalInfoKind(this.label);

  /// A short Japanese name for the learner.
  final String label;
}

final _email = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}',
);

// A run of digits joined by phone-number separators (learners also type the
// long vowel mark "ー" or a dash). _isPhone decides whether it is a number.
final _digitRun = RegExp(r'\(?\+?\d(?:[-‐−–—ー.()\s]{0,2}\d)*');
final _digitGroup = RegExp(r'\d+');

// 〒123-4567 or 123-4567 (but not the middle of 090-1234-5678).
final _postalCode = RegExp(r'〒\s*\d{3}-?\d{4}|(?<![\d-])\d{3}-\d{4}(?![\d-])');

/// The kinds of personal information [text] seems to contain, in a fixed
/// order; empty when nothing was found.
List<PersonalInfoKind> findPersonalInfo(String text) {
  final normalized = _halfWidth(text);
  return [
    if (_email.hasMatch(normalized)) PersonalInfoKind.email,
    if (_digitRun.allMatches(normalized).any((run) => _isPhone(run.group(0)!)))
      PersonalInfoKind.phone,
    if (_postalCode.hasMatch(normalized)) PersonalInfoKind.postalCode,
  ];
}

/// Full-width ASCII (e.g. "０９０－１２３４" or "ｔａｒｏ＠") as half-width,
/// the part of the server's NFKC normalization these patterns rely on.
String _halfWidth(String text) => String.fromCharCodes([
  for (final rune in text.runes)
    if (rune >= 0xFF01 && rune <= 0xFF5E)
      rune - 0xFEE0
    else if (rune == 0x3000)
      0x20
    else
      rune,
]);

/// Whether consecutive digit groups of [run] spell a Japanese phone number,
/// so "090-1234-5678" is found even when other numbers follow it.
bool _isPhone(String run) {
  final groups = [for (final m in _digitGroup.allMatches(run)) m.group(0)!];
  if (groups.isEmpty) {
    return false;
  }
  if (run.replaceFirst(RegExp(r'^\(+'), '').startsWith('+') &&
      groups.first == '81') {
    groups[0] = '0'; // +81-90-... is 090-...
  }
  for (var start = 0; start < groups.length; start++) {
    var digits = '';
    for (final group in groups.skip(start)) {
      digits += group;
      if (digits.startsWith('0') &&
          (digits.length == 10 || digits.length == 11)) {
        return true;
      }
      if (digits.length > 11) {
        break;
      }
    }
  }
  return false;
}
