import 'dart:convert';
import 'dart:io';

import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';

/// The real Unit 1 content (content/units/u1/*.yaml) as the JSON the seed
/// writes to Firestore: `test/fixtures/unit1.json` holds
/// `{"lessons": [...], "exercises": [...], "answerKeys": {...}}`.
///
/// Regenerate after changing the YAML by converting it with any YAML → JSON
/// tool (the files are already camelCase; `answerKeys` is the
/// `*.answers.yaml` content, used only by the fake API in tests).
class Unit1Fixture {
  Unit1Fixture._(this._json);

  factory Unit1Fixture.load() => Unit1Fixture._(
    jsonDecode(File('test/fixtures/unit1.json').readAsStringSync())
        as Map<String, Object?>,
  );

  final Map<String, Object?> _json;

  List<Map<String, Object?>> get lessonJsons =>
      (_json['lessons']! as List).cast<Map<String, Object?>>();

  List<Map<String, Object?>> get exerciseJsons =>
      (_json['exercises']! as List).cast<Map<String, Object?>>();

  Map<String, Map<String, Object?>> get answerKeys =>
      (_json['answerKeys']! as Map).cast<String, Map<String, Object?>>();

  /// A deep copy, so tests can modify it.
  Map<String, Object?> exerciseJson(String id) =>
      _copy(exerciseJsons.singleWhere((e) => e['id'] == id));

  Map<String, Object?> lessonJson(String id) =>
      _copy(lessonJsons.singleWhere((l) => l['id'] == id));

  List<Lesson> get lessons => [for (final j in lessonJsons) Lesson.fromJson(j)];

  List<Exercise> get exercises => [
    for (final j in exerciseJsons) Exercise.fromJson(j),
  ];

  Lesson lesson(String id) => Lesson.fromJson(lessonJson(id));

  T exercise<T extends Exercise>(String id) =>
      Exercise.fromJson(exerciseJson(id)) as T;

  static Map<String, Object?> _copy(Map<String, Object?> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

final unit1 = Unit1Fixture.load();
