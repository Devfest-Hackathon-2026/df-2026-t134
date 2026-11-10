/// Request and response bodies of `POST /v1/live-checks` and
/// `POST /v1/live-checks/{sessionId}/lookup` (Q10, see docs/openapi.json
/// `StartLiveCheckRequest`, `LiveCheckStarted`, `LiveCheckBlocked`,
/// `LookupRequest`, `LookupResponse` and `WebSource`).
library;

import 'exercise.dart';
import 'json_fields.dart';
import 'prompt_evaluation.dart';

/// Longest prompt the API accepts at all; an exercise's `maxLength` may be
/// shorter. Counted like [promptLength].
const maxLiveCheckPromptLength = 400;

/// A web page Google Search returned for the grounded answer.
class WebSource {
  const WebSource({required this.title, required this.uri});

  /// Usually the site's domain (e.g. `wikipedia.org`).
  final String title;

  /// May be a Google redirect to the page; open it as is.
  final String uri;

  factory WebSource.fromJson(Object? json) {
    const what = 'WebSource';
    final map = readObject(json, what, allowed: const {'title', 'uri'});
    return WebSource(
      title: readText(map, 'title', what),
      uri: readString(map, 'uri', what),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WebSource && other.title == title && other.uri == uri;

  @override
  int get hashCode => Object.hash(title, uri);
}

List<WebSource> readSources(Map<String, Object?> map, String what) =>
    List.unmodifiable(
      readList(map, 'sources', what, minItems: 0).map(WebSource.fromJson),
    );

class StartLiveCheckRequest {
  /// [prompt] must already be trimmed (the API strips whitespace and then
  /// requires 1..[maxLiveCheckPromptLength] characters).
  StartLiveCheckRequest({required this.exerciseId, required this.prompt}) {
    if (!isContractId(exerciseId)) {
      throw ArgumentError.value(exerciseId, 'exerciseId', 'not a contract id');
    }
    final length = promptLength(prompt);
    if (prompt.trim() != prompt ||
        length < 1 ||
        length > maxLiveCheckPromptLength) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'must be trimmed and 1..$maxLiveCheckPromptLength characters',
      );
    }
  }

  final String exerciseId;
  final String prompt;

  Map<String, Object?> toJson() => {'exerciseId': exerciseId, 'prompt': prompt};
}

/// The answer of `/v1/live-checks`, discriminated by `status`.
sealed class StartLiveCheckResponse {
  const StartLiveCheckResponse();

  factory StartLiveCheckResponse.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('StartLiveCheckResponse must be an object', json);
    }
    return switch (json['status']) {
      'generated' => LiveCheckStarted.fromJson(json),
      'blocked' => LiveCheckBlocked.fromJson(json),
      final status => throw FormatException(
        'Unknown live check status',
        status,
      ),
    };
  }
}

/// The AI answered; [errorCount] is the maximum, not the actual error count.
final class LiveCheckStarted extends StartLiveCheckResponse {
  LiveCheckStarted({
    required this.sessionId,
    required List<Sentence> sentences,
    required this.errorCount,
    required this.lookupsLeft,
  }) : sentences = List.unmodifiable(sentences);

  final String sessionId;

  /// Indexes are 0..n-1 in order.
  final List<Sentence> sentences;
  final int errorCount;
  final int lookupsLeft;

  factory LiveCheckStarted.fromJson(Object? json) {
    const what = 'LiveCheckStarted';
    final map = readObject(
      json,
      what,
      allowed: const {
        'status',
        'sessionId',
        'sentences',
        'errorCount',
        'lookupsLeft',
      },
    );
    final sentences = [
      for (final item in readList(
        map,
        'sentences',
        what,
        minItems: 2,
        maxItems: 12,
      ))
        Sentence.fromJson(item),
    ];
    for (final (position, sentence) in sentences.indexed) {
      if (sentence.index != position) {
        throw FormatException('$what.sentences must be indexed 0..n-1', map);
      }
    }
    final errorCount = readInt(map, 'errorCount', what, min: 0, max: 2);
    if (errorCount >= sentences.length) {
      throw FormatException('$what.errorCount must be < sentence count', map);
    }
    return LiveCheckStarted(
      sessionId: readId(map, 'sessionId', what),
      sentences: sentences,
      errorCount: errorCount,
      lookupsLeft: readInt(map, 'lookupsLeft', what, min: 0),
    );
  }
}

/// The prompt was not sent to the model (personal information, off the
/// theme, inappropriate). Nothing was recorded; the learner edits and sends
/// again.
final class LiveCheckBlocked extends StartLiveCheckResponse {
  LiveCheckBlocked({
    required List<PromptBlockReason> reasons,
    required this.message,
  }) : reasons = List.unmodifiable(reasons);

  final List<PromptBlockReason> reasons;

  /// A Japanese explanation for the learner (may be empty).
  final String message;

  factory LiveCheckBlocked.fromJson(Object? json) {
    const what = 'LiveCheckBlocked';
    final map = readObject(
      json,
      what,
      allowed: const {'status', 'reasons', 'message'},
    );
    return LiveCheckBlocked(
      reasons: [
        for (final reason in readList(map, 'reasons', what, minItems: 1))
          PromptBlockReason.fromWire(reason),
      ],
      message: readText(map, 'message', what),
    );
  }
}

class LookupRequest {
  LookupRequest(this.sentenceIndex) {
    if (sentenceIndex < 0) {
      throw ArgumentError.value(sentenceIndex, 'sentenceIndex', 'negative');
    }
  }

  final int sentenceIndex;

  Map<String, Object?> toJson() => {'sentenceIndex': sentenceIndex};
}

/// The Google Search sources of one sentence. For a rewritten sentence they
/// are the sources of the correct one, which is how the learner can find out.
class LookupResponse {
  LookupResponse({
    required this.sentenceIndex,
    required List<WebSource> sources,
    required this.lookupsLeft,
  }) : sources = List.unmodifiable(sources);

  final int sentenceIndex;

  /// May be empty: no page supports this sentence.
  final List<WebSource> sources;
  final int lookupsLeft;

  factory LookupResponse.fromJson(Object? json) {
    const what = 'LookupResponse';
    final map = readObject(
      json,
      what,
      allowed: const {'sentenceIndex', 'sources', 'lookupsLeft'},
    );
    return LookupResponse(
      sentenceIndex: readInt(map, 'sentenceIndex', what, min: 0),
      sources: readSources(map, what),
      lookupsLeft: readInt(map, 'lookupsLeft', what, min: 0),
    );
  }
}
