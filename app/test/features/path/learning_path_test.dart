import 'package:ailearn/features/path/learning_path.dart';
import 'package:ailearn/models/progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

List<(String, LessonStatus)> statuses(LearningPath path) => [
  for (final unit in path.units)
    for (final item in unit.lessons) (item.lesson.id, item.status),
];

void main() {
  // Deliberately shuffled: order comes from `order`, not from the input.
  final units = [unit('u2', 2), unit('u1', 1)];
  final lessons = [
    lesson('u2-l1', 'u2', 1),
    lesson('u1-l2', 'u1', 2),
    lesson('u1-l1', 'u1', 1),
  ];

  test('orders units and lessons by order', () {
    final path = buildLearningPath(
      units: units,
      lessons: lessons,
      progress: Progress.empty,
    );

    expect(path.units.map((u) => u.unit.id), ['u1', 'u2']);
    expect(statuses(path).map((s) => s.$1), ['u1-l1', 'u1-l2', 'u2-l1']);
  });

  test('a new user can only open the first lesson', () {
    final path = buildLearningPath(
      units: units,
      lessons: lessons,
      progress: Progress.empty,
    );

    expect(statuses(path), [
      ('u1-l1', LessonStatus.unlocked),
      ('u1-l2', LessonStatus.locked),
      ('u2-l1', LessonStatus.locked),
    ]);
    expect(path.nextLessonId, 'u1-l1');
  });

  test('completing a lesson unlocks the next one, also across units', () {
    final afterFirst = buildLearningPath(
      units: units,
      lessons: lessons,
      progress: progressWith({'u1-l1'}),
    );
    expect(statuses(afterFirst), [
      ('u1-l1', LessonStatus.completed),
      ('u1-l2', LessonStatus.unlocked),
      ('u2-l1', LessonStatus.locked),
    ]);

    final afterUnit = buildLearningPath(
      units: units,
      lessons: lessons,
      progress: progressWith({'u1-l1', 'u1-l2'}),
    );
    expect(statuses(afterUnit), [
      ('u1-l1', LessonStatus.completed),
      ('u1-l2', LessonStatus.completed),
      ('u2-l1', LessonStatus.unlocked),
    ]);
    expect(afterUnit.nextLessonId, 'u2-l1');
  });

  test('a unit without lessons does not block the next unit', () {
    final path = buildLearningPath(
      units: [unit('u1', 1), unit('u2', 2), unit('u3', 3)],
      lessons: [lesson('u1-l1', 'u1', 1), lesson('u3-l1', 'u3', 1)],
      progress: progressWith({'u1-l1'}),
    );

    expect(path.units[1].lessons, isEmpty);
    expect(statuses(path), [
      ('u1-l1', LessonStatus.completed),
      ('u3-l1', LessonStatus.unlocked),
    ]);
  });

  test('everything completed has no next lesson; unknown ids are ignored', () {
    final path = buildLearningPath(
      units: units,
      lessons: lessons,
      progress: progressWith({'u1-l1', 'u1-l2', 'u2-l1', 'removed-lesson'}),
    );

    expect(statuses(path).every((s) => s.$2 == LessonStatus.completed), isTrue);
    expect(path.nextLessonId, isNull);
  });

  test('no content gives an empty path', () {
    final path = buildLearningPath(
      units: const [],
      lessons: const [],
      progress: Progress.empty,
    );

    expect(path.units, isEmpty);
    expect(path.nextLessonId, isNull);
  });

  test('inconsistent content fails loudly', () {
    expect(
      () => buildLearningPath(
        units: [unit('u1', 1)],
        lessons: [lesson('u9-l1', 'u9', 1)],
        progress: Progress.empty,
      ),
      throwsFormatException,
    );
    expect(
      () => buildLearningPath(
        units: [unit('u1', 1), unit('u2', 1)],
        lessons: const [],
        progress: Progress.empty,
      ),
      throwsFormatException,
    );
    expect(
      () => buildLearningPath(
        units: [unit('u1', 1)],
        lessons: [lesson('u1-l1', 'u1', 1), lesson('u1-l2', 'u1', 1)],
        progress: Progress.empty,
      ),
      throwsFormatException,
    );
  });
}
