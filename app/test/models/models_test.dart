import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/progress.dart';
import 'package:ailearn/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> unitJson() => {
  'id': 'u1',
  'order': 1,
  'title': 'AI ってなに？',
  'description': '次の単語を予測するしくみ',
  'level': 1,
};

Map<String, Object?> lessonJson() => {
  'id': 'u1-l1',
  'unitId': 'u1',
  'order': 1,
  'title': 'AI は予測マシン',
  'exerciseIds': ['u1-l1-q1', 'u1-l1-q2'],
};

Map<String, Object?> progressJson() => {
  'xp': 30,
  'streakDays': 2,
  'lastStudiedOn': '2026-11-08',
  'freezeTickets': 1,
  'completedLessonIds': ['u1-l1'],
};

Map<String, Object?> profileJson() => {
  'displayName': 'ひかり',
  'grade': 'h1',
  'createdAt': '2026-11-09T01:02:03.000Z',
};

void main() {
  group('Unit', () {
    test('parses the contract JSON', () {
      final unit = Unit.fromJson(unitJson());

      expect(unit.id, 'u1');
      expect(unit.order, 1);
      expect(unit.title, 'AI ってなに？');
      expect(unit.description, '次の単語を予測するしくみ');
      expect(unit.level, 1);
    });

    test('fails on missing, mistyped, unknown or out-of-range fields', () {
      expect(
        () => Unit.fromJson(unitJson()..remove('title')),
        throwsFormatException,
      );
      expect(
        () => Unit.fromJson(unitJson()..['order'] = '1'),
        throwsFormatException,
      );
      expect(
        () => Unit.fromJson(unitJson()..['order'] = 0),
        throwsFormatException,
      );
      expect(
        () => Unit.fromJson(unitJson()..['level'] = 5),
        throwsFormatException,
      );
      expect(
        () => Unit.fromJson(unitJson()..['id'] = 'U 1'),
        throwsFormatException,
      );
      expect(
        () => Unit.fromJson(unitJson()..['extra'] = 1),
        throwsFormatException,
      );
      expect(() => Unit.fromJson('u1'), throwsFormatException);
    });
  });

  group('Lesson', () {
    test('parses the contract JSON; a missing intro is null', () {
      final lesson = Lesson.fromJson(lessonJson());

      expect(lesson.id, 'u1-l1');
      expect(lesson.unitId, 'u1');
      expect(lesson.order, 1);
      expect(lesson.exerciseIds, ['u1-l1-q1', 'u1-l1-q2']);
      expect(lesson.intro, isNull);
    });

    test('parses the intro speech; a missing audioPath is null', () {
      final lesson = Lesson.fromJson(
        lessonJson()..['intro'] = {'text': 'はじめよう！'},
      );

      expect(lesson.intro?.text, 'はじめよう！');
      expect(lesson.intro?.audioPath, isNull);

      final withAudio = Lesson.fromJson(
        lessonJson()
          ..['intro'] = {'text': 'はじめよう！', 'audioPath': 'audio/u1-l1.mp3'},
      );
      expect(withAudio.intro?.audioPath, 'audio/u1-l1.mp3');
    });

    test('fails on malformed fields', () {
      expect(
        () => Lesson.fromJson(lessonJson()..['exerciseIds'] = <String>[]),
        throwsFormatException,
      );
      expect(
        () => Lesson.fromJson(
          lessonJson()..['exerciseIds'] = List.filled(13, 'q'),
        ),
        throwsFormatException,
      );
      expect(
        () => Lesson.fromJson(lessonJson()..['exerciseIds'] = [1]),
        throwsFormatException,
      );
      expect(
        () => Lesson.fromJson(lessonJson()..remove('unitId')),
        throwsFormatException,
      );
      expect(
        () => Lesson.fromJson(lessonJson()..['intro'] = {'text': ''}),
        throwsFormatException,
      );
      expect(
        () => Lesson.fromJson(lessonJson()..['intro'] = {'voice': 'x'}),
        throwsFormatException,
      );
    });
  });

  group('Progress', () {
    test('parses the contract JSON', () {
      final progress = Progress.fromJson(progressJson());

      expect(progress.xp, 30);
      expect(progress.streakDays, 2);
      expect(progress.lastStudiedOn, DateTime.utc(2026, 11, 8));
      expect(progress.freezeTickets, 1);
      expect(progress.completedLessonIds, {'u1-l1'});
    });

    test('a missing lastStudiedOn is null', () {
      final progress = Progress.fromJson(
        progressJson()..remove('lastStudiedOn'),
      );

      expect(progress.lastStudiedOn, isNull);
    });

    test('fails on malformed fields', () {
      expect(
        () => Progress.fromJson(progressJson()..remove('xp')),
        throwsFormatException,
      );
      expect(
        () => Progress.fromJson(progressJson()..['xp'] = -1),
        throwsFormatException,
      );
      expect(
        () => Progress.fromJson(progressJson()..['freezeTickets'] = 4),
        throwsFormatException,
      );
      expect(
        () =>
            Progress.fromJson(progressJson()..['lastStudiedOn'] = '2026/11/08'),
        throwsFormatException,
      );
      expect(
        () =>
            Progress.fromJson(progressJson()..['completedLessonIds'] = 'u1-l1'),
        throwsFormatException,
      );
    });

    test('empty progress has nothing completed', () {
      expect(Progress.empty.xp, 0);
      expect(Progress.empty.streakDays, 0);
      expect(Progress.empty.completedLessonIds, isEmpty);
    });
  });

  group('UserProfile', () {
    test('parses the contract JSON', () {
      final profile = UserProfile.fromJson(profileJson());

      expect(profile.displayName, 'ひかり');
      expect(profile.grade, Grade.h1);
      expect(profile.createdAt, DateTime.utc(2026, 11, 9, 1, 2, 3));
    });

    test('fails on malformed fields', () {
      expect(
        () => UserProfile.fromJson(profileJson()..['grade'] = 'e1'),
        throwsFormatException,
      );
      expect(
        () => UserProfile.fromJson(profileJson()..remove('createdAt')),
        throwsFormatException,
      );
      expect(
        () => UserProfile.fromJson(profileJson()..['email'] = 'a@example.com'),
        throwsFormatException,
      );
    });
  });

  group('nickname', () {
    test('is trimmed and must be 1..20 characters', () {
      expect(checkNickname('  ひかり  '), isNull);
      expect(checkNickname('   '), NicknameProblem.empty);
      expect(checkNickname('あ' * 20), isNull);
      expect(checkNickname('あ' * 21), NicknameProblem.tooLong);

      final draft = ProfileDraft(displayName: '  ひかり ', grade: Grade.j1);
      expect(draft.displayName, 'ひかり');
    });

    test('ProfileDraft refuses invalid nicknames', () {
      expect(
        () => ProfileDraft(displayName: ' ', grade: Grade.j1),
        throwsArgumentError,
      );
    });

    test('grades map to the stored codes', () {
      expect(Grade.values.map((g) => g.code), [
        'j1',
        'j2',
        'j3',
        'h1',
        'h2',
        'h3',
      ]);
      expect(Grade.values.map((g) => g.label), [
        '中1',
        '中2',
        '中3',
        '高1',
        '高2',
        '高3',
      ]);
    });
  });
}
