import 'content.dart';
import 'json_fields.dart';
import 'story.dart';

/// The `type` discriminator shared by exercises, answers and results.
enum ExerciseType {
  choice('choice'),
  order('order'),
  fillBlank('fill_blank'),
  hallucination('hallucination'),
  prompt('prompt'),
  liveCheck('live_check'),
  story('story');

  const ExerciseType(this.wireName);

  /// Value of the `type` field in contract JSON.
  final String wireName;

  static ExerciseType fromWire(Object? value, String what) {
    for (final type in values) {
      if (type.wireName == value) {
        return type;
      }
    }
    throw FormatException('$what.type is not a known exercise type', value);
  }
}

/// An option of a choice question, an order item or a blank's choice.
class Option {
  const Option({required this.id, required this.text});

  final String id;
  final String text;

  factory Option.fromJson(Object? json) {
    const what = 'Option';
    final map = readObject(json, what, allowed: const {'id', 'text'});
    return Option(
      id: readId(map, 'id', what),
      text: readString(map, 'text', what),
    );
  }
}

/// `exercises/{id}` (content/schema/exercise.schema.json), without the
/// answer: answer keys stay on the server.
sealed class Exercise {
  const Exercise({
    required this.id,
    required this.lessonId,
    required this.question,
    this.intro,
  });

  final String id;
  final String lessonId;
  final String question;

  /// Optional mascot line shown before the question.
  final Speech? intro;

  ExerciseType get type;

  /// Parses any exercise type; the `type` field picks the class.
  factory Exercise.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('Exercise must be a JSON object', json);
    }
    return switch (ExerciseType.fromWire(json['type'], 'Exercise')) {
      ExerciseType.choice => ChoiceExercise.fromJson(json),
      ExerciseType.order => OrderExercise.fromJson(json),
      ExerciseType.fillBlank => FillBlankExercise.fromJson(json),
      ExerciseType.hallucination => HallucinationExercise.fromJson(json),
      ExerciseType.prompt => PromptExercise.fromJson(json),
      ExerciseType.liveCheck => LiveCheckExercise.fromJson(json),
      ExerciseType.story => StoryExercise.fromJson(json),
    };
  }
}

const _baseFields = {'id', 'lessonId', 'question', 'type', 'intro'};

/// Reads the fields every exercise has after checking the allowed keys.
({String id, String lessonId, String question, Speech? intro}) _readBase(
  Map<String, Object?> map,
  String what,
) {
  final intro = map['intro'];
  return (
    id: readId(map, 'id', what),
    lessonId: readId(map, 'lessonId', what),
    question: readString(map, 'question', what),
    intro: intro == null ? null : Speech.fromJson(intro),
  );
}

List<Option> _readOptions(
  Map<String, Object?> map,
  String key,
  String what, {
  required int maxItems,
}) {
  final options = List<Option>.unmodifiable(
    readList(
      map,
      key,
      what,
      minItems: 2,
      maxItems: maxItems,
    ).map(Option.fromJson),
  );
  _requireUniqueIds(options.map((o) => o.id), '$what.$key', map);
  return options;
}

void _requireUniqueIds(Iterable<String> ids, String where, Object? source) {
  final list = ids.toList();
  if (list.toSet().length != list.length) {
    throw FormatException('$where has duplicate ids', source);
  }
}

/// Q1: pick one option.
final class ChoiceExercise extends Exercise {
  const ChoiceExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.options,
  });

  final List<Option> options;

  @override
  ExerciseType get type => ExerciseType.choice;

  factory ChoiceExercise.fromJson(Object? json) {
    const what = 'ChoiceExercise';
    final map = readObject(json, what, allowed: {..._baseFields, 'options'});
    _requireType(map, ExerciseType.choice, what);
    final base = _readBase(map, what);
    return ChoiceExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      options: _readOptions(map, 'options', what, maxItems: 6),
    );
  }
}

/// Q3: put the items in the right order. [items] are in authoring order;
/// the app shuffles them before display.
final class OrderExercise extends Exercise {
  const OrderExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.items,
  });

  final List<Option> items;

  @override
  ExerciseType get type => ExerciseType.order;

  factory OrderExercise.fromJson(Object? json) {
    const what = 'OrderExercise';
    final map = readObject(json, what, allowed: {..._baseFields, 'items'});
    _requireType(map, ExerciseType.order, what);
    final base = _readBase(map, what);
    return OrderExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      items: _readOptions(map, 'items', what, maxItems: 8),
    );
  }
}

class Blank {
  const Blank({required this.id, required this.options});

  final String id;
  final List<Option> options;

  factory Blank.fromJson(Object? json) {
    const what = 'Blank';
    final map = readObject(json, what, allowed: const {'id', 'options'});
    return Blank(
      id: readId(map, 'id', what),
      options: _readOptions(map, 'options', what, maxItems: 6),
    );
  }
}

/// A piece of a fill-in-the-blank template.
sealed class TemplatePart {
  const TemplatePart();
}

final class TemplateText extends TemplatePart {
  const TemplateText(this.text);

  final String text;
}

final class TemplateSlot extends TemplatePart {
  const TemplateSlot(this.blank);

  final Blank blank;
}

/// Q3: choose an option for every blank. [template] marks each blank as
/// `{{blankId}}`, exactly once.
final class FillBlankExercise extends Exercise {
  const FillBlankExercise._({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.template,
    required this.blanks,
    required this.parts,
  });

  /// Throws [FormatException] when the placeholders in [template] do not
  /// match [blanks] one to one.
  factory FillBlankExercise({
    required String id,
    required String lessonId,
    required String question,
    Speech? intro,
    required String template,
    required List<Blank> blanks,
  }) => FillBlankExercise._(
    id: id,
    lessonId: lessonId,
    question: question,
    intro: intro,
    template: template,
    blanks: blanks,
    parts: _splitTemplate(template, blanks),
  );

  final String template;
  final List<Blank> blanks;

  /// [template] split into text and slots, in reading order.
  final List<TemplatePart> parts;

  @override
  ExerciseType get type => ExerciseType.fillBlank;

  factory FillBlankExercise.fromJson(Object? json) {
    const what = 'FillBlankExercise';
    final map = readObject(
      json,
      what,
      allowed: {..._baseFields, 'template', 'blanks'},
    );
    _requireType(map, ExerciseType.fillBlank, what);
    final base = _readBase(map, what);
    final blanks = List<Blank>.unmodifiable(
      readList(
        map,
        'blanks',
        what,
        minItems: 1,
        maxItems: 4,
      ).map(Blank.fromJson),
    );
    _requireUniqueIds(blanks.map((b) => b.id), '$what.blanks', map);
    return FillBlankExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      template: readString(map, 'template', what),
      blanks: blanks,
    );
  }
}

final _placeholder = RegExp(r'\{\{([^{}]*)\}\}');

List<TemplatePart> _splitTemplate(String template, List<Blank> blanks) {
  final byId = {for (final blank in blanks) blank.id: blank};
  final seen = <String>{};
  final parts = <TemplatePart>[];
  var start = 0;
  for (final match in _placeholder.allMatches(template)) {
    final blank = byId[match.group(1)];
    if (blank == null || !seen.add(blank.id)) {
      throw FormatException(
        'Template placeholder ${match.group(0)} is unknown or repeated',
        template,
      );
    }
    if (match.start > start) {
      parts.add(TemplateText(template.substring(start, match.start)));
    }
    parts.add(TemplateSlot(blank));
    start = match.end;
  }
  if (start < template.length) {
    parts.add(TemplateText(template.substring(start)));
  }
  if (seen.length != blanks.length) {
    throw FormatException('Template is missing some blanks', template);
  }
  return List.unmodifiable(parts);
}

class Sentence {
  const Sentence({required this.index, required this.text});

  final int index;
  final String text;

  factory Sentence.fromJson(Object? json) {
    const what = 'Sentence';
    final map = readObject(json, what, allowed: const {'index', 'text'});
    return Sentence(
      index: readInt(map, 'index', what, min: 0),
      text: readString(map, 'text', what),
    );
  }
}

/// Q2: an AI answer split into sentences; the learner taps the wrong ones.
/// Played with `HallucinationExerciseView` in the lesson player.
final class HallucinationExercise extends Exercise {
  const HallucinationExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.topic,
    required this.sentences,
    required this.errorCount,
  });

  final String topic;

  /// Indexes are 0..n-1 in order.
  final List<Sentence> sentences;
  final int errorCount;

  @override
  ExerciseType get type => ExerciseType.hallucination;

  factory HallucinationExercise.fromJson(Object? json) {
    const what = 'HallucinationExercise';
    final map = readObject(
      json,
      what,
      allowed: {..._baseFields, 'topic', 'sentences', 'errorCount'},
    );
    _requireType(map, ExerciseType.hallucination, what);
    final base = _readBase(map, what);
    final sentences = List<Sentence>.unmodifiable(
      readList(
        map,
        'sentences',
        what,
        minItems: 2,
        maxItems: 12,
      ).map(Sentence.fromJson),
    );
    for (final (position, sentence) in sentences.indexed) {
      if (sentence.index != position) {
        throw FormatException('$what.sentences must be indexed 0..n-1', map);
      }
    }
    final errorCount = readInt(map, 'errorCount', what, min: 1, max: 3);
    if (errorCount >= sentences.length) {
      throw FormatException('$what.errorCount must be < sentence count', map);
    }
    return HallucinationExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      topic: readString(map, 'topic', what),
      sentences: sentences,
      errorCount: errorCount,
    );
  }
}

/// Q4: write a prompt for [task]; graded by Gemini (PR-13).
/// Played with lib/features/lesson/widgets/prompt_exercise_view.dart.
final class PromptExercise extends Exercise {
  const PromptExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.task,
    required this.maxLength,
  });

  /// Contract default when the document omits `maxLength`.
  static const defaultMaxLength = 400;

  final String task;
  final int maxLength;

  @override
  ExerciseType get type => ExerciseType.prompt;

  factory PromptExercise.fromJson(Object? json) {
    const what = 'PromptExercise';
    final map = readObject(
      json,
      what,
      allowed: {..._baseFields, 'task', 'maxLength'},
    );
    _requireType(map, ExerciseType.prompt, what);
    final base = _readBase(map, what);
    return PromptExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      task: readString(map, 'task', what),
      maxLength: map['maxLength'] == null
          ? defaultMaxLength
          : readInt(map, 'maxLength', what, min: 20, max: 1000),
    );
  }
}

/// Q10: the learner asks Gemini about [theme] with their own prompt, then
/// finds the sentences the server secretly rewrote, looking up the Google
/// Search sources at most [lookupLimit] times. The answer and the session
/// come from `/v1/live-checks`; played with
/// lib/features/lesson/widgets/live_check_exercise_view.dart.
final class LiveCheckExercise extends Exercise {
  LiveCheckExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.theme,
    required List<String> suggestions,
    required this.errorCount,
    required this.lookupLimit,
    required this.maxLength,
  }) : suggestions = List.unmodifiable(suggestions);

  /// Contract defaults when the document omits them.
  static const defaultLookupLimit = 2;
  static const defaultMaxLength = 200;

  final String theme;

  /// Example prompts the learner can tap (1–4).
  final List<String> suggestions;

  /// How many sentences the server rewrites (1–2).
  final int errorCount;
  final int lookupLimit;

  /// Longest prompt, in characters as the API counts them.
  final int maxLength;

  @override
  ExerciseType get type => ExerciseType.liveCheck;

  factory LiveCheckExercise.fromJson(Object? json) {
    const what = 'LiveCheckExercise';
    final map = readObject(
      json,
      what,
      allowed: {
        ..._baseFields,
        'theme',
        'suggestions',
        'errorCount',
        'lookupLimit',
        'maxLength',
      },
    );
    _requireType(map, ExerciseType.liveCheck, what);
    final base = _readBase(map, what);
    return LiveCheckExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      theme: readString(map, 'theme', what),
      suggestions: [
        for (final item in readList(
          map,
          'suggestions',
          what,
          minItems: 1,
          maxItems: 4,
        ))
          if (item is String && item.trim().isNotEmpty)
            item
          else
            throw FormatException('$what.suggestions must hold texts', map),
      ],
      errorCount: readInt(map, 'errorCount', what, min: 1, max: 2),
      lookupLimit: map['lookupLimit'] == null
          ? defaultLookupLimit
          : readInt(map, 'lookupLimit', what, min: 0, max: 5),
      maxLength: map['maxLength'] == null
          ? defaultMaxLength
          : readInt(map, 'maxLength', what, min: 20, max: 400),
    );
  }
}

/// A short picture-story (kamishibai): [scenes] play first, then [question]
/// asks what to do and the learner picks one of [options]. What happens next
/// comes back in the `StoryResult`.
/// Played with lib/features/lesson/widgets/story_exercise_view.dart.
final class StoryExercise extends Exercise {
  const StoryExercise({
    required super.id,
    required super.lessonId,
    required super.question,
    super.intro,
    required this.title,
    required this.scenes,
    required this.options,
  });

  final String title;
  final List<Scene> scenes;
  final List<Option> options;

  @override
  ExerciseType get type => ExerciseType.story;

  factory StoryExercise.fromJson(Object? json) {
    const what = 'StoryExercise';
    final map = readObject(
      json,
      what,
      allowed: {..._baseFields, 'title', 'scenes', 'options'},
    );
    _requireType(map, ExerciseType.story, what);
    final base = _readBase(map, what);
    return StoryExercise(
      id: base.id,
      lessonId: base.lessonId,
      question: base.question,
      intro: base.intro,
      title: readString(map, 'title', what),
      scenes: readScenes(map, 'scenes', what, minItems: 1, maxItems: 8),
      options: _readOptions(map, 'options', what, maxItems: 4),
    );
  }
}

void _requireType(Map<String, Object?> map, ExerciseType type, String what) {
  if (map['type'] != type.wireName) {
    throw FormatException('$what.type must be "${type.wireName}"', map);
  }
}
