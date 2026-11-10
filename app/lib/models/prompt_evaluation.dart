/// Request and response bodies of `POST /v1/prompt/evaluate` (Q4, see
/// docs/openapi.json `EvaluatePromptRequest`, `PromptEvaluated`,
/// `PromptBlocked` and `RubricScores`).
library;

import 'answer.dart';
import 'json_fields.dart';

/// Longest prompt the API accepts at all; an exercise's `maxLength` may be
/// shorter.
const maxPromptLength = 1000;

/// The length of [text] as the API counts it (Unicode code points, like
/// Python's `len`), not UTF-16 code units or grapheme clusters.
int promptLength(String text) => text.runes.length;

class EvaluatePromptRequest {
  /// [prompt] must already be trimmed (the API strips whitespace and then
  /// requires 1..[maxPromptLength] characters).
  EvaluatePromptRequest({required this.exerciseId, required this.prompt}) {
    if (!isContractId(exerciseId)) {
      throw ArgumentError.value(exerciseId, 'exerciseId', 'not a contract id');
    }
    final length = promptLength(prompt);
    if (prompt.trim() != prompt || length < 1 || length > maxPromptLength) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'must be trimmed and 1..$maxPromptLength characters',
      );
    }
  }

  final String exerciseId;
  final String prompt;

  Map<String, Object?> toJson() => {'exerciseId': exerciseId, 'prompt': prompt};
}

/// One rubric axis, worth 0–2 points (requirements §5.3).
enum RubricAxis { purpose, context, constraints, format, safety }

/// Points per rubric axis, each 0–2.
class RubricScores {
  const RubricScores({
    required this.purpose,
    required this.context,
    required this.constraints,
    required this.format,
    required this.safety,
  });

  static const maxPerAxis = 2;

  final int purpose;
  final int context;
  final int constraints;
  final int format;
  final int safety;

  int of(RubricAxis axis) => switch (axis) {
    RubricAxis.purpose => purpose,
    RubricAxis.context => context,
    RubricAxis.constraints => constraints,
    RubricAxis.format => format,
    RubricAxis.safety => safety,
  };

  factory RubricScores.fromJson(Object? json) {
    const what = 'RubricScores';
    final map = readObject(
      json,
      what,
      allowed: {for (final axis in RubricAxis.values) axis.name},
    );
    int read(RubricAxis axis) =>
        readInt(map, axis.name, what, min: 0, max: maxPerAxis);
    return RubricScores(
      purpose: read(RubricAxis.purpose),
      context: read(RubricAxis.context),
      constraints: read(RubricAxis.constraints),
      format: read(RubricAxis.format),
      safety: read(RubricAxis.safety),
    );
  }
}

/// The answer of `/v1/prompt/evaluate`, discriminated by `status`.
sealed class PromptEvaluationResponse {
  const PromptEvaluationResponse();

  factory PromptEvaluationResponse.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('PromptEvaluationResponse must be an object', json);
    }
    return switch (json['status']) {
      'evaluated' => PromptEvaluated.fromJson(json),
      'blocked' => PromptBlocked.fromJson(json),
      final status => throw FormatException(
        'Unknown prompt evaluation status',
        status,
      ),
    };
  }
}

/// The prompt was graded and recorded as an attempt.
final class PromptEvaluated extends PromptEvaluationResponse {
  PromptEvaluated({
    required this.attemptId,
    required this.total,
    required this.scores,
    required this.goodPoint,
    required List<String> improvements,
    required this.hint,
    required this.progress,
  }) : improvements = List.unmodifiable(improvements);

  /// From this total (out of [maxTotal]) the prompt counts as good, like the
  /// server's `PROMPT_PASSING_SCORE`.
  static const passingTotal = 6;
  static const maxTotal = 10;

  /// Can be read aloud later: `/v1/tts` takes this id (PR-15).
  final String attemptId;
  final int total;
  final RubricScores scores;
  final String goodPoint;

  /// One or two things to improve.
  final List<String> improvements;
  final String hint;
  final ProgressSnapshot progress;

  bool get passed => total >= passingTotal;

  factory PromptEvaluated.fromJson(Object? json) {
    const what = 'PromptEvaluated';
    final map = readObject(
      json,
      what,
      allowed: const {
        'status',
        'attemptId',
        'total',
        'scores',
        'goodPoint',
        'improvements',
        'hint',
        'progress',
      },
    );
    return PromptEvaluated(
      attemptId: readId(map, 'attemptId', what),
      total: readInt(map, 'total', what, min: 0, max: maxTotal),
      scores: RubricScores.fromJson(map['scores']),
      goodPoint: readText(map, 'goodPoint', what),
      improvements: [
        for (final item in readList(
          map,
          'improvements',
          what,
          minItems: 1,
          maxItems: 2,
        ))
          if (item is String)
            item
          else
            throw FormatException('$what.improvements must hold strings', map),
      ],
      hint: readText(map, 'hint', what),
      progress: ProgressSnapshot.fromJson(map['progress']),
    );
  }
}

/// Why a prompt was not sent to the model.
enum PromptBlockReason {
  personalInfo,
  inappropriate,
  offTopic;

  static PromptBlockReason fromWire(Object? value) => switch (value) {
    'personal_info' => personalInfo,
    'inappropriate' => inappropriate,
    'off_topic' => offTopic,
    _ => throw FormatException('Unknown prompt block reason', value),
  };
}

/// The prompt was not graded (e.g. it contains personal information). Not an
/// attempt: nothing was recorded, and the learner can edit and send again.
final class PromptBlocked extends PromptEvaluationResponse {
  PromptBlocked({
    required List<PromptBlockReason> reasons,
    required this.message,
  }) : reasons = List.unmodifiable(reasons);

  final List<PromptBlockReason> reasons;

  /// A Japanese explanation for the learner (may be empty).
  final String message;

  factory PromptBlocked.fromJson(Object? json) {
    const what = 'PromptBlocked';
    final map = readObject(
      json,
      what,
      allowed: const {'status', 'reasons', 'message'},
    );
    return PromptBlocked(
      reasons: [
        for (final reason in readList(map, 'reasons', what, minItems: 1))
          PromptBlockReason.fromWire(reason),
      ],
      message: readText(map, 'message', what),
    );
  }
}
