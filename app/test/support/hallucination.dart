import 'dart:convert';
import 'dart:io';

import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';

import 'unit1.dart';

/// A hallucination exercise for lesson u1-l1 with its answer key
/// (`test/fixtures/hallucination.json`). Sentences 1 and 4 are wrong; the
/// key lists its errors out of order on purpose, as authors may.
class HallucinationFixture {
  HallucinationFixture._(this._json);

  factory HallucinationFixture.load() => HallucinationFixture._(
    jsonDecode(File('test/fixtures/hallucination.json').readAsStringSync())
        as Map<String, Object?>,
  );

  final Map<String, Object?> _json;

  static const exerciseId = 'u1-l1-q7';

  /// Indexes of the wrong sentences.
  static const wrongIndexes = [1, 4];

  HallucinationExercise get exercise =>
      Exercise.fromJson(_json['exercise']) as HallucinationExercise;

  Map<String, Object?> get answerKey =>
      (_json['answerKey']! as Map).cast<String, Object?>();

  /// Unit 1 answer keys plus this exercise's key.
  Map<String, Map<String, Object?>> get answerKeys => {
    ...unit1.answerKeys,
    exerciseId: answerKey,
  };

  /// Lesson u1-l1 with this exercise inserted at [position].
  Lesson lessonU1L1({required int position}) {
    final json = unit1.lessonJson('u1-l1');
    (json['exerciseIds']! as List).insert(position, exerciseId);
    return Lesson.fromJson(json);
  }

  /// Unit 1 lessons with u1-l1 replaced by [lessonU1L1].
  List<Lesson> unit1Lessons({required int position}) => [
    for (final l in unit1.lessons)
      if (l.id == 'u1-l1') lessonU1L1(position: position) else l,
  ];

  /// Unit 1 exercises plus this one.
  List<Exercise> get unit1Exercises => [...unit1.exercises, exercise];
}

final hallucinationFixture = HallucinationFixture.load();
