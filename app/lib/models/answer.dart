/// Request and response bodies of `POST /v1/answers` and
/// `POST /v1/lessons/{lessonId}/complete` (docs/openapi.json).
library;

import 'exercise.dart';
import 'json_fields.dart';
import 'live_check.dart';
import 'story.dart';

/// The learner's answer, discriminated by `type`. Prompt exercises are graded
/// by `/v1/prompt/evaluate` instead, so they have no answer here.
sealed class Answer {
  const Answer();

  ExerciseType get type;

  Map<String, Object?> toJson();
}

final class ChoiceAnswer extends Answer {
  const ChoiceAnswer(this.optionId);

  final String optionId;

  @override
  ExerciseType get type => ExerciseType.choice;

  @override
  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'optionId': optionId,
  };
}

final class OrderAnswer extends Answer {
  OrderAnswer(List<String> itemIds) : itemIds = List.unmodifiable(itemIds);

  final List<String> itemIds;

  @override
  ExerciseType get type => ExerciseType.order;

  @override
  Map<String, Object?> toJson() => {'type': type.wireName, 'itemIds': itemIds};
}

final class FillBlankAnswer extends Answer {
  FillBlankAnswer(Map<String, String> selectedOptions)
    : selectedOptions = Map.unmodifiable(selectedOptions);

  /// Blank id → option id.
  final Map<String, String> selectedOptions;

  @override
  ExerciseType get type => ExerciseType.fillBlank;

  @override
  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'selectedOptions': selectedOptions,
  };
}

final class HallucinationAnswer extends Answer {
  HallucinationAnswer(List<int> sentenceIndexes)
    : sentenceIndexes = List.unmodifiable(sentenceIndexes);

  /// Sentences the learner thinks are wrong; may be empty.
  final List<int> sentenceIndexes;

  @override
  ExerciseType get type => ExerciseType.hallucination;

  @override
  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'sentenceIndexes': sentenceIndexes,
  };
}

/// Q10: the sentences of the live check session the learner thinks are wrong.
final class LiveCheckAnswer extends Answer {
  LiveCheckAnswer({required this.sessionId, required List<int> sentenceIndexes})
    : sentenceIndexes = List.unmodifiable(sentenceIndexes) {
    if (!isContractId(sessionId)) {
      throw ArgumentError.value(sessionId, 'sessionId', 'not a contract id');
    }
  }

  final String sessionId;
  final List<int> sentenceIndexes;

  @override
  ExerciseType get type => ExerciseType.liveCheck;

  @override
  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'sessionId': sessionId,
    'sentenceIndexes': sentenceIndexes,
  };
}

final class StoryAnswer extends Answer {
  const StoryAnswer(this.optionId);

  final String optionId;

  @override
  ExerciseType get type => ExerciseType.story;

  @override
  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'optionId': optionId,
  };
}

class SubmitAnswerRequest {
  const SubmitAnswerRequest({required this.exerciseId, required this.answer});

  final String exerciseId;
  final Answer answer;

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'answer': answer.toJson(),
  };
}

/// Learner progress right after an action.
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.xp,
    required this.xpGained,
    required this.streakDays,
  });

  /// Total XP after the action.
  final int xp;

  /// XP added by this action.
  final int xpGained;
  final int streakDays;

  factory ProgressSnapshot.fromJson(Object? json) {
    const what = 'ProgressSnapshot';
    final map = readObject(
      json,
      what,
      allowed: const {'xp', 'xpGained', 'streakDays'},
    );
    return ProgressSnapshot(
      xp: readInt(map, 'xp', what, min: 0),
      xpGained: readInt(map, 'xpGained', what, min: 0),
      streakDays: readInt(map, 'streakDays', what, min: 0),
    );
  }
}

/// The graded result with the correct answer, discriminated by `type`.
sealed class AnswerResult {
  const AnswerResult();

  ExerciseType get type;

  factory AnswerResult.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('AnswerResult must be a JSON object', json);
    }
    return switch (ExerciseType.fromWire(json['type'], 'AnswerResult')) {
      ExerciseType.choice => ChoiceResult.fromJson(json),
      ExerciseType.order => OrderResult.fromJson(json),
      ExerciseType.fillBlank => FillBlankResult.fromJson(json),
      ExerciseType.hallucination => HallucinationResult.fromJson(json),
      ExerciseType.prompt => throw FormatException(
        'AnswerResult cannot be of type prompt',
        json,
      ),
      ExerciseType.liveCheck => LiveCheckResult.fromJson(json),
      ExerciseType.story => StoryResult.fromJson(json),
    };
  }
}

final class ChoiceResult extends AnswerResult {
  const ChoiceResult({
    required this.correctOptionId,
    required this.explanation,
  });

  final String correctOptionId;

  /// May contain `\n` line breaks.
  final String explanation;

  @override
  ExerciseType get type => ExerciseType.choice;

  factory ChoiceResult.fromJson(Object? json) {
    const what = 'ChoiceResult';
    final map = readObject(
      json,
      what,
      allowed: const {'type', 'correctOptionId', 'explanation'},
    );
    return ChoiceResult(
      correctOptionId: readId(map, 'correctOptionId', what),
      explanation: readText(map, 'explanation', what),
    );
  }
}

final class OrderResult extends AnswerResult {
  const OrderResult({required this.correctOrder, required this.explanation});

  final List<String> correctOrder;
  final String explanation;

  @override
  ExerciseType get type => ExerciseType.order;

  factory OrderResult.fromJson(Object? json) {
    const what = 'OrderResult';
    final map = readObject(
      json,
      what,
      allowed: const {'type', 'correctOrder', 'explanation'},
    );
    return OrderResult(
      correctOrder: readIdList(map, 'correctOrder', what, minItems: 0),
      explanation: readText(map, 'explanation', what),
    );
  }
}

final class FillBlankResult extends AnswerResult {
  const FillBlankResult({
    required this.correctOptions,
    required this.explanation,
  });

  /// Blank id → option id.
  final Map<String, String> correctOptions;
  final String explanation;

  @override
  ExerciseType get type => ExerciseType.fillBlank;

  factory FillBlankResult.fromJson(Object? json) {
    const what = 'FillBlankResult';
    final map = readObject(
      json,
      what,
      allowed: const {'type', 'correctOptions', 'explanation'},
    );
    return FillBlankResult(
      correctOptions: readIdMap(map, 'correctOptions', what),
      explanation: readText(map, 'explanation', what),
    );
  }
}

enum HallucinationErrorType {
  number,
  date,
  name,
  fakeSource,
  causality,
  fact;

  static HallucinationErrorType fromWire(Object? value) => switch (value) {
    'number' => number,
    'date' => date,
    'name' => name,
    'fake_source' => fakeSource,
    'causality' => causality,
    'fact' => fact,
    _ => throw FormatException('Unknown hallucination error type', value),
  };
}

class HallucinationError {
  const HallucinationError({
    required this.index,
    required this.errorType,
    required this.correction,
    required this.tip,
  });

  final int index;
  final HallucinationErrorType errorType;
  final String correction;
  final String tip;

  factory HallucinationError.fromJson(Object? json) {
    const what = 'HallucinationError';
    final map = readObject(
      json,
      what,
      allowed: const {'index', 'errorType', 'correction', 'tip'},
    );
    return HallucinationError(
      index: readInt(map, 'index', what, min: 0),
      errorType: HallucinationErrorType.fromWire(map['errorType']),
      correction: readString(map, 'correction', what),
      tip: readString(map, 'tip', what),
    );
  }
}

final class HallucinationResult extends AnswerResult {
  const HallucinationResult({
    required this.errors,
    required this.found,
    required this.missed,
    required this.falseAlarms,
  });

  final List<HallucinationError> errors;

  /// Wrong sentences the learner tapped.
  final List<int> found;

  /// Wrong sentences the learner did not tap.
  final List<int> missed;

  /// Correct sentences the learner tapped.
  final List<int> falseAlarms;

  @override
  ExerciseType get type => ExerciseType.hallucination;

  factory HallucinationResult.fromJson(Object? json) {
    const what = 'HallucinationResult';
    final map = readObject(
      json,
      what,
      allowed: const {'type', 'errors', 'found', 'missed', 'falseAlarms'},
    );
    return HallucinationResult(
      errors: List.unmodifiable(
        readList(
          map,
          'errors',
          what,
          minItems: 0,
        ).map(HallucinationError.fromJson),
      ),
      found: readIntList(map, 'found', what, min: 0),
      missed: readIntList(map, 'missed', what, min: 0),
      falseAlarms: readIntList(map, 'falseAlarms', what, min: 0),
    );
  }
}

/// Q10: like [HallucinationResult] for the session's sentences, with every
/// Google Search source of the correct answer.
final class LiveCheckResult extends AnswerResult {
  LiveCheckResult({
    required List<HallucinationError> errors,
    required List<int> found,
    required List<int> missed,
    required List<int> falseAlarms,
    required List<WebSource> sources,
  }) : errors = List.unmodifiable(errors),
       found = List.unmodifiable(found),
       missed = List.unmodifiable(missed),
       falseAlarms = List.unmodifiable(falseAlarms),
       sources = List.unmodifiable(sources);

  /// The rewritten sentences; `correction` is the original sentence.
  final List<HallucinationError> errors;
  final List<int> found;
  final List<int> missed;
  final List<int> falseAlarms;
  final List<WebSource> sources;

  @override
  ExerciseType get type => ExerciseType.liveCheck;

  /// The same verdicts as a [HallucinationResult], for the shared review.
  HallucinationResult get asHallucination => HallucinationResult(
    errors: errors,
    found: found,
    missed: missed,
    falseAlarms: falseAlarms,
  );

  factory LiveCheckResult.fromJson(Object? json) {
    const what = 'LiveCheckResult';
    final map = readObject(
      json,
      what,
      allowed: const {
        'type',
        'errors',
        'found',
        'missed',
        'falseAlarms',
        'sources',
      },
    );
    return LiveCheckResult(
      errors: [
        for (final item in readList(map, 'errors', what, minItems: 0))
          HallucinationError.fromJson(item),
      ],
      found: readIntList(map, 'found', what, min: 0),
      missed: readIntList(map, 'missed', what, min: 0),
      falseAlarms: readIntList(map, 'falseAlarms', what, min: 0),
      sources: readSources(map, what),
    );
  }
}

final class StoryResult extends AnswerResult {
  StoryResult({
    required this.bestOptionId,
    required List<Scene> outcome,
    required this.explanation,
  }) : outcome = List.unmodifiable(outcome);

  final String bestOptionId;

  /// What happens after the learner's choice, played before the feedback.
  final List<Scene> outcome;
  final String explanation;

  @override
  ExerciseType get type => ExerciseType.story;

  factory StoryResult.fromJson(Object? json) {
    const what = 'StoryResult';
    final map = readObject(
      json,
      what,
      allowed: const {'type', 'bestOptionId', 'outcome', 'explanation'},
    );
    return StoryResult(
      bestOptionId: readId(map, 'bestOptionId', what),
      // The answer key has 1..4 scenes per outcome.
      outcome: readScenes(map, 'outcome', what, minItems: 1, maxItems: 4),
      explanation: readText(map, 'explanation', what),
    );
  }
}

class SubmitAnswerResponse {
  const SubmitAnswerResponse({
    required this.attemptId,
    required this.correct,
    required this.result,
    required this.progress,
  });

  final String attemptId;
  final bool correct;
  final AnswerResult result;
  final ProgressSnapshot progress;

  factory SubmitAnswerResponse.fromJson(Object? json) {
    const what = 'SubmitAnswerResponse';
    final map = readObject(
      json,
      what,
      allowed: const {'attemptId', 'correct', 'result', 'progress'},
    );
    return SubmitAnswerResponse(
      attemptId: readId(map, 'attemptId', what),
      correct: readBool(map, 'correct', what),
      result: AnswerResult.fromJson(map['result']),
      progress: ProgressSnapshot.fromJson(map['progress']),
    );
  }
}

class CompleteLessonResponse {
  const CompleteLessonResponse({
    required this.lessonId,
    required this.progress,
  });

  final String lessonId;
  final ProgressSnapshot progress;

  factory CompleteLessonResponse.fromJson(Object? json) {
    const what = 'CompleteLessonResponse';
    final map = readObject(json, what, allowed: const {'lessonId', 'progress'});
    return CompleteLessonResponse(
      lessonId: readId(map, 'lessonId', what),
      progress: ProgressSnapshot.fromJson(map['progress']),
    );
  }
}
