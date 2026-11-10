import 'json_fields.dart';

/// `progress/{uid}` (docs/schemas/firestore/progress.schema.json).
///
/// Written only by the server; the app reads it.
class Progress {
  const Progress({
    required this.xp,
    required this.streakDays,
    required this.lastStudiedOn,
    required this.freezeTickets,
    required this.completedLessonIds,
  });

  /// A user who has not finished any lesson yet has no progress document.
  static const empty = Progress(
    xp: 0,
    streakDays: 0,
    lastStudiedOn: null,
    freezeTickets: 0,
    completedLessonIds: {},
  );

  final int xp;
  final int streakDays;

  /// Calendar date (UTC midnight) of the last study day, if any.
  final DateTime? lastStudiedOn;
  final int freezeTickets;
  final Set<String> completedLessonIds;

  factory Progress.fromJson(Object? json) {
    const what = 'Progress';
    final map = readObject(
      json,
      what,
      allowed: const {
        'xp',
        'streakDays',
        'lastStudiedOn',
        'freezeTickets',
        'completedLessonIds',
      },
    );
    return Progress(
      xp: readInt(map, 'xp', what, min: 0),
      streakDays: readInt(map, 'streakDays', what, min: 0),
      lastStudiedOn: readOptionalDate(map, 'lastStudiedOn', what),
      freezeTickets: readInt(map, 'freezeTickets', what, min: 0, max: 3),
      completedLessonIds: Set.unmodifiable(
        readIdList(map, 'completedLessonIds', what, minItems: 0),
      ),
    );
  }
}
