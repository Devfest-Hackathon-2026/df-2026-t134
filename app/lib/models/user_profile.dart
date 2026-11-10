import 'json_fields.dart';

/// School year. [code] is the value stored in Firestore.
enum Grade {
  j1('j1', '中1'),
  j2('j2', '中2'),
  j3('j3', '中3'),
  h1('h1', '高1'),
  h2('h2', '高2'),
  h3('h3', '高3');

  const Grade(this.code, this.label);

  final String code;

  /// Japanese label shown in the UI.
  final String label;

  static Grade fromCode(Object? code) {
    for (final grade in values) {
      if (grade.code == code) {
        return grade;
      }
    }
    throw FormatException('Unknown grade', code);
  }
}

/// `users/{uid}` (docs/schemas/firestore/user_profile.schema.json).
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.grade,
    required this.createdAt,
  });

  /// Nickname, never the real name.
  final String displayName;
  final Grade grade;
  final DateTime createdAt;

  factory UserProfile.fromJson(Object? json) {
    const what = 'UserProfile';
    final map = readObject(
      json,
      what,
      allowed: const {'displayName', 'grade', 'createdAt'},
    );
    return UserProfile(
      displayName: readString(map, 'displayName', what),
      grade: Grade.fromCode(map['grade']),
      createdAt: readDateTime(map, 'createdAt', what),
    );
  }
}

/// Why a nickname typed by the user cannot be used.
enum NicknameProblem { empty, tooLong }

/// Limit from firebase/firestore.rules (`displayName.size() <= 20`).
const nicknameMaxLength = 20;

/// Validates user input. Returns null when [raw] is usable.
NicknameProblem? checkNickname(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return NicknameProblem.empty;
  }
  // String.length counts UTF-16 code units, which is never less than the
  // character count used by the rules, so this stays within the rule.
  if (trimmed.length > nicknameMaxLength) {
    return NicknameProblem.tooLong;
  }
  return null;
}

/// A validated profile that is about to be created.
class ProfileDraft {
  ProfileDraft._(this.displayName, this.grade);

  /// Throws [ArgumentError] when [displayName] fails [checkNickname];
  /// callers validate user input with [checkNickname] first.
  factory ProfileDraft({required String displayName, required Grade grade}) {
    final problem = checkNickname(displayName);
    if (problem != null) {
      throw ArgumentError.value(displayName, 'displayName', problem.name);
    }
    return ProfileDraft._(displayName.trim(), grade);
  }

  /// Trimmed nickname.
  final String displayName;
  final Grade grade;
}
