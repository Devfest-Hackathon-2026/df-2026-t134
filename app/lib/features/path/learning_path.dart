import '../../models/content.dart';
import '../../models/progress.dart';

enum LessonStatus { locked, unlocked, completed }

class PathLesson {
  const PathLesson({required this.lesson, required this.status});

  final Lesson lesson;
  final LessonStatus status;
}

class PathUnit {
  const PathUnit({required this.unit, required this.lessons});

  final Unit unit;
  final List<PathLesson> lessons;
}

/// Units and lessons in path order with the lock state of each lesson.
class LearningPath {
  const LearningPath({required this.units, required this.progress});

  final List<PathUnit> units;
  final Progress progress;

  /// The first lesson the user can play but has not completed yet.
  String? get nextLessonId {
    for (final unit in units) {
      for (final item in unit.lessons) {
        if (item.status == LessonStatus.unlocked) {
          return item.lesson.id;
        }
      }
    }
    return null;
  }
}

/// Orders units by `order` and lessons by `order` within their unit.
///
/// A lesson is unlocked when it is the first lesson of the whole path or the
/// lesson before it (in path order, across units) is completed.
///
/// Throws [FormatException] for inconsistent content: a lesson pointing at a
/// missing unit, or two units / two lessons of a unit sharing an `order`.
LearningPath buildLearningPath({
  required List<Unit> units,
  required List<Lesson> lessons,
  required Progress progress,
}) {
  final sortedUnits = [...units]..sort((a, b) => a.order.compareTo(b.order));
  _requireDistinctOrders(sortedUnits.map((u) => u.order), 'units');

  final lessonsByUnit = {for (final unit in sortedUnits) unit.id: <Lesson>[]};
  for (final lesson in lessons) {
    final bucket = lessonsByUnit[lesson.unitId];
    if (bucket == null) {
      throw FormatException(
        'Lesson ${lesson.id} refers to a missing unit',
        lesson.unitId,
      );
    }
    bucket.add(lesson);
  }

  final completed = progress.completedLessonIds;
  // Starts as true so the very first lesson is unlocked.
  var previousCompleted = true;
  final pathUnits = <PathUnit>[];
  for (final unit in sortedUnits) {
    final unitLessons = lessonsByUnit[unit.id]!
      ..sort((a, b) => a.order.compareTo(b.order));
    _requireDistinctOrders(
      unitLessons.map((l) => l.order),
      'lessons of ${unit.id}',
    );
    final items = <PathLesson>[];
    for (final lesson in unitLessons) {
      final isCompleted = completed.contains(lesson.id);
      final status = isCompleted
          ? LessonStatus.completed
          : previousCompleted
          ? LessonStatus.unlocked
          : LessonStatus.locked;
      items.add(PathLesson(lesson: lesson, status: status));
      previousCompleted = isCompleted;
    }
    pathUnits.add(PathUnit(unit: unit, lessons: List.unmodifiable(items)));
  }
  return LearningPath(units: List.unmodifiable(pathUnits), progress: progress);
}

void _requireDistinctOrders(Iterable<int> sortedOrders, String what) {
  int? previous;
  for (final order in sortedOrders) {
    if (order == previous) {
      throw FormatException('Duplicate order among $what', order);
    }
    previous = order;
  }
}
