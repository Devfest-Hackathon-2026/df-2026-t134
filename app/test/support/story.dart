import 'dart:convert';
import 'dart:io';

import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';

import 'fake_api.dart';
import 'fakes.dart';

/// The real story lesson u1-l4 (content/units/u1/u1-l4*.yaml) as the seed
/// writes it to Firestore, with the generated picture and voice paths:
/// `test/fixtures/story.json` holds
/// `{"lesson": {...}, "exercises": [...], "answerKeys": {...}}`.
///
/// Regenerate after changing the YAML or the media files: in the tools
/// container, take `build_documents(_with_media(content, content_dir))` (what
/// `seed` writes) and keep lesson u1-l4, its exercises and answer keys.
class StoryFixture {
  StoryFixture._(this._json);

  factory StoryFixture.load() => StoryFixture._(
    jsonDecode(File('test/fixtures/story.json').readAsStringSync())
        as Map<String, Object?>,
  );

  final Map<String, Object?> _json;

  static const lessonId = 'u1-l4';

  Map<String, Object?> get lessonJson =>
      _copy(_json['lesson']! as Map<String, Object?>);

  List<Map<String, Object?>> get exerciseJsons => [
    for (final e in _json['exercises']! as List)
      _copy(e as Map<String, Object?>),
  ];

  Map<String, Map<String, Object?>> get answerKeys =>
      (_json['answerKeys']! as Map).cast<String, Map<String, Object?>>();

  Lesson get lesson => Lesson.fromJson(lessonJson);

  List<StoryExercise> get exercises => [
    for (final j in exerciseJsons) StoryExercise.fromJson(j),
  ];

  /// A path with only this lesson (so it is unlocked) and the fake API.
  ({FakeContentRepository content, FakeLearningApi api}) setup() => (
    content: FakeContentRepository(
      units: [unit('u1', 1)],
      lessons: [lesson],
      exercises: exercises,
    ),
    api: FakeLearningApi(
      answerKeys: answerKeys,
      lessonExercises: {lessonId: lesson.exerciseIds},
    ),
  );

  static Map<String, Object?> _copy(Map<String, Object?> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

final storyFixture = StoryFixture.load();
