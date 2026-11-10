/// Picture-story (kamishibai) parts shared by `StoryExercise` and
/// `StoryResult` (content/schema/exercise.schema.json, docs/openapi.json).
library;

import 'json_fields.dart';

/// Who says a scene's line. Each speaker has its own voice.
enum Speaker {
  narrator('narrator', 'ナレーション'),
  mascot('mascot', 'マスコット'),
  student('student', 'ユイ'),
  friend('friend', 'ソウタ'),
  teacher('teacher', '先生'),
  ai('ai', 'AI アシスタント');

  const Speaker(this.wireName, this.label);

  /// Value of the `speaker` field in contract JSON.
  final String wireName;

  /// The name shown on the scene (the story's original characters).
  final String label;

  static Speaker fromWire(Object? value, String what) {
    for (final speaker in values) {
      if (speaker.wireName == value) {
        return speaker;
      }
    }
    throw FormatException('$what.speaker is not a known speaker', value);
  }
}

/// A scene's picture. [imagePath] (Cloud Storage) is set once the picture
/// has been generated; without it the app shows a placeholder.
class Illustration {
  const Illustration({required this.prompt, this.imagePath});

  /// What the picture shows (written for the image model; also a fallback
  /// description, but never shown as content).
  final String prompt;
  final String? imagePath;

  factory Illustration.fromJson(Object? json) {
    const what = 'Illustration';
    final map = readObject(json, what, allowed: const {'prompt', 'imagePath'});
    return Illustration(
      prompt: readString(map, 'prompt', what),
      imagePath: readOptionalString(map, 'imagePath', what),
    );
  }
}

/// One panel of a story: who speaks, what they say, and optionally a picture
/// and the pre-generated voice.
class Scene {
  const Scene({
    required this.speaker,
    required this.text,
    this.audioPath,
    this.illustration,
  });

  final Speaker speaker;

  /// May contain `\n` line breaks. Always shown (subtitles).
  final String text;
  final String? audioPath;
  final Illustration? illustration;

  factory Scene.fromJson(Object? json) {
    const what = 'Scene';
    final map = readObject(
      json,
      what,
      allowed: const {'speaker', 'text', 'audioPath', 'illustration'},
    );
    final illustration = map['illustration'];
    return Scene(
      speaker: Speaker.fromWire(map['speaker'], what),
      text: readString(map, 'text', what),
      audioPath: readOptionalString(map, 'audioPath', what),
      illustration: illustration == null
          ? null
          : Illustration.fromJson(illustration),
    );
  }
}

/// [scenes] parsed with [minItems]..[maxItems] entries.
List<Scene> readScenes(
  Map<String, Object?> map,
  String key,
  String what, {
  required int minItems,
  required int maxItems,
}) => List.unmodifiable(
  readList(
    map,
    key,
    what,
    minItems: minItems,
    maxItems: maxItems,
  ).map(Scene.fromJson),
);

/// The picture to show at [index] of [scenes]: the scene's own, or else the
/// last one before it (a kamishibai keeps the picture until the next one).
Illustration? pictureAt(List<Scene> scenes, int index) {
  for (var i = index; i >= 0; i--) {
    if (scenes[i].illustration case final illustration?) {
      return illustration;
    }
  }
  return null;
}
