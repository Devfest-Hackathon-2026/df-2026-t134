import 'json_fields.dart';

/// `units/{id}` (content/schema/unit.schema.json).
class Unit {
  const Unit({
    required this.id,
    required this.order,
    required this.title,
    required this.description,
    required this.level,
  });

  final String id;

  /// Position on the learning path, starting at 1.
  final int order;
  final String title;
  final String description;

  /// Target level Lv1..Lv4 (docs/REQUIREMENTS.md §4.1).
  final int level;

  factory Unit.fromJson(Object? json) {
    const what = 'Unit';
    final map = readObject(
      json,
      what,
      allowed: const {'id', 'order', 'title', 'description', 'level'},
    );
    return Unit(
      id: readId(map, 'id', what),
      order: readInt(map, 'order', what, min: 1),
      title: readString(map, 'title', what),
      description: readString(map, 'description', what),
      level: readInt(map, 'level', what, min: 1, max: 4),
    );
  }
}

/// A line spoken by the mascot.
class Speech {
  const Speech({required this.text, this.audioPath});

  final String text;

  /// Set when the audio has been pre-generated.
  final String? audioPath;

  factory Speech.fromJson(Object? json) {
    const what = 'Speech';
    final map = readObject(json, what, allowed: const {'text', 'audioPath'});
    return Speech(
      text: readString(map, 'text', what),
      audioPath: readOptionalString(map, 'audioPath', what),
    );
  }
}

/// `lessons/{id}` (content/schema/lesson.schema.json).
class Lesson {
  const Lesson({
    required this.id,
    required this.unitId,
    required this.order,
    required this.title,
    required this.exerciseIds,
    this.intro,
  });

  final String id;
  final String unitId;

  /// Position within the unit, starting at 1.
  final int order;
  final String title;
  final List<String> exerciseIds;
  final Speech? intro;

  factory Lesson.fromJson(Object? json) {
    const what = 'Lesson';
    final map = readObject(
      json,
      what,
      allowed: const {'id', 'unitId', 'order', 'title', 'exerciseIds', 'intro'},
    );
    final intro = map['intro'];
    return Lesson(
      id: readId(map, 'id', what),
      unitId: readId(map, 'unitId', what),
      order: readInt(map, 'order', what, min: 1),
      title: readString(map, 'title', what),
      exerciseIds: readIdList(
        map,
        'exerciseIds',
        what,
        minItems: 1,
        maxItems: 12,
      ),
      intro: intro == null ? null : Speech.fromJson(intro),
    );
  }
}
