import 'dart:convert';

import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/features/lesson/personal_info_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory learning API behind a [MockClient], so tests exercise the
/// real [ApiClient] JSON handling. Grades with the answer keys it is given
/// and follows the XP rules of PR-08 in a simplified way.
class FakeLearningApi {
  FakeLearningApi({
    required this._answerKeys,
    required this._lessonExercises,
    this.xp = 0,
    this.streakDays = 0,
  });

  final Map<String, Map<String, Object?>> _answerKeys;

  /// Lesson id → exercise ids, for the 409 check of `/complete`.
  final Map<String, List<String>> _lessonExercises;

  int xp;
  int streakDays;
  final attempted = <String>{};
  final _correctOnce = <String>{};
  final completed = <String>{};

  /// Every request as (path, decoded JSON body or null).
  final requests = <(String, Object?)>[];

  final _failures = <String, List<Object>>{};

  /// `/v1/prompt/evaluate` with AI grading off answers 503
  /// `upstream_unavailable` (like a local stack without Vertex AI).
  bool promptGradingOn = true;

  /// The total (0–10) the fake grader gives every prompt.
  int promptTotal = 7;

  /// Bodies sent to `/v1/prompt/evaluate`.
  List<Map<String, Object?>> get promptBodies => [
    for (final (path, body) in requests)
      if (path == '/v1/prompt/evaluate') body! as Map<String, Object?>,
  ];

  /// The next call to [path] answers with [failure] instead: an
  /// [http.Response] or an exception to throw (e.g. a network error).
  void failNext(String path, Object failure) =>
      (_failures[path] ??= []).add(failure);

  static http.Response errorResponse(int status, String code) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': 'fake $code'},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// Bodies sent to `/v1/answers`.
  List<Map<String, Object?>> get answerBodies => [
    for (final (path, body) in requests)
      if (path == '/v1/answers') body! as Map<String, Object?>,
  ];

  ApiClient client({IdTokenProvider? idToken}) => ApiClient(
    baseUrl: Uri.parse('http://localhost:8000'),
    httpClient: MockClient(_handle),
    idToken: idToken ?? () async => 'test-token',
    appCheckToken: noAppCheckToken,
  );

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/v1/health') {
      return _json({'status': 'ok', 'version': '0.1.0', 'env': 'test'});
    }
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    requests.add((path, body));
    final queued = _failures[path];
    if (queued != null && queued.isNotEmpty) {
      final failure = queued.removeAt(0);
      if (failure is http.Response) {
        return failure;
      }
      throw failure;
    }
    if (path == '/v1/answers') {
      return _answer(body! as Map<String, Object?>);
    }
    if (path == '/v1/prompt/evaluate') {
      return _evaluatePrompt(body! as Map<String, Object?>);
    }
    if (path == '/v1/live-checks') {
      return _startLiveCheck(body! as Map<String, Object?>);
    }
    final lookup = RegExp(r'^/v1/live-checks/([^/]+)/lookup$').firstMatch(path);
    if (lookup != null) {
      return _lookup(lookup.group(1)!, body! as Map<String, Object?>);
    }
    final complete = RegExp(r'^/v1/lessons/([^/]+)/complete$').firstMatch(path);
    if (complete != null) {
      return _complete(complete.group(1)!);
    }
    return errorResponse(404, 'not_found');
  }

  http.Response _answer(Map<String, Object?> body) {
    final exerciseId = body['exerciseId']! as String;
    final answer = body['answer']! as Map<String, Object?>;
    final key = _answerKeys[exerciseId];
    if (key == null) {
      return errorResponse(404, 'not_found');
    }
    if (answer['type'] != key['type']) {
      return errorResponse(400, 'bad_request');
    }
    if (key['type'] == 'live_check') {
      return _answerLiveCheck(exerciseId, answer);
    }
    final (correct, result) = switch (key['type']) {
      'choice' => (
        answer['optionId'] == key['correctOptionId'],
        {
          'type': 'choice',
          'correctOptionId': key['correctOptionId'],
          'explanation': key['explanation'],
        },
      ),
      'order' => (
        jsonEncode(answer['itemIds']) == jsonEncode(key['correctOrder']),
        {
          'type': 'order',
          'correctOrder': key['correctOrder'],
          'explanation': key['explanation'],
        },
      ),
      'fill_blank' => (
        _sameMap(answer['selectedOptions'], key['correctOptions']),
        {
          'type': 'fill_blank',
          'correctOptions': key['correctOptions'],
          'explanation': key['explanation'],
        },
      ),
      'hallucination' => _hallucination(answer, key),
      'story' => _story(answer, key),
      _ => throw UnsupportedError('fake grading of ${key['type']}'),
    };
    attempted.add(exerciseId);
    final gained = correct && _correctOnce.add(exerciseId) ? 10 : 0;
    xp += gained;
    return _json({
      'attemptId': 'attempt${requests.length}',
      'correct': correct,
      'result': result,
      'progress': {'xp': xp, 'xpGained': gained, 'streakDays': streakDays},
    });
  }

  /// Blocks personal information like the server, otherwise grades with
  /// [promptTotal] and records an attempt (XP for the first passing one).
  http.Response _evaluatePrompt(Map<String, Object?> body) {
    final exerciseId = body['exerciseId']! as String;
    final prompt = body['prompt']! as String;
    if (findPersonalInfo(prompt).isNotEmpty) {
      return _json({
        'status': 'blocked',
        'reasons': ['personal_info'],
        'message': '電話番号のような個人情報が入っているみたい。',
      });
    }
    if (!promptGradingOn) {
      return errorResponse(503, 'upstream_unavailable');
    }
    attempted.add(exerciseId);
    final passed = promptTotal >= 6;
    final gained = passed && _correctOnce.add(exerciseId) ? 10 : 0;
    xp += gained;
    final perAxis = [for (var i = 0; i < 5; i++) (promptTotal - i + 4) ~/ 5];
    return _json({
      'status': 'evaluated',
      'attemptId': 'attempt${requests.length}',
      'total': promptTotal,
      'scores': {
        'purpose': perAxis[0],
        'context': perAxis[1],
        'constraints': perAxis[2],
        'format': perAxis[3],
        'safety': perAxis[4],
      },
      'goodPoint': '目的がはっきりしているね。',
      'improvements': ['人数や予算を書くと、もっと合ったアイデアになるよ。'],
      'hint': '答えをどんな形でほしいか、書いてみよう。',
      'progress': {'xp': xp, 'xpGained': gained, 'streakDays': streakDays},
    });
  }

  http.Response _complete(String lessonId) {
    final exerciseIds = _lessonExercises[lessonId];
    if (exerciseIds == null) {
      return errorResponse(404, 'not_found');
    }
    if (!exerciseIds.every(attempted.contains)) {
      return errorResponse(409, 'conflict');
    }
    final gained = completed.add(lessonId) ? 20 : 0;
    xp += gained;
    streakDays += 1;
    return _json({
      'lessonId': lessonId,
      'progress': {'xp': xp, 'xpGained': gained, 'streakDays': streakDays},
    });
  }

  /// Like the server: correct when every wrong sentence and no correct one
  /// was tapped; the lists are sorted.
  static (bool, Map<String, Object?>) _hallucination(
    Map<String, Object?> answer,
    Map<String, Object?> key,
  ) {
    final errors = [
      for (final e in key['errors']! as List) e as Map<String, Object?>,
    ]..sort((a, b) => (a['index']! as int).compareTo(b['index']! as int));
    final wrong = {for (final e in errors) e['index']! as int};
    final tapped = (answer['sentenceIndexes']! as List).cast<int>().toSet();
    List<int> sorted(Set<int> set) => set.toList()..sort();
    final missed = sorted(wrong.difference(tapped));
    final falseAlarms = sorted(tapped.difference(wrong));
    return (
      missed.isEmpty && falseAlarms.isEmpty,
      {
        'type': 'hallucination',
        'errors': errors,
        'found': sorted(tapped.intersection(wrong)),
        'missed': missed,
        'falseAlarms': falseAlarms,
      },
    );
  }

  // ---- Live check (Q10) ----------------------------------------------------

  /// What the fake AI answers to every `/v1/live-checks` prompt; null answers
  /// 503 `upstream_unavailable` (AI off, like a local stack).
  FakeLiveCheckAnswer? liveCheckAnswer;

  /// Lookups per session, like an exercise's `lookupLimit`.
  int liveCheckLookupLimit = 2;

  /// A prompt containing this is judged off the theme by the fake AI.
  static const offTopicWord = 'ゲーム';

  /// Session id → (exercise id, lookups used, answered).
  final liveCheckSessions =
      <String, ({String exerciseId, int lookupsUsed, bool answered})>{};

  /// Bodies sent to `/v1/live-checks`.
  List<Map<String, Object?>> get liveCheckBodies => [
    for (final (path, body) in requests)
      if (path == '/v1/live-checks') body! as Map<String, Object?>,
  ];

  /// Sentence indexes sent to the lookup endpoint, in order.
  List<int> get lookupIndexes => [
    for (final (path, body) in requests)
      if (path.endsWith('/lookup'))
        (body! as Map<String, Object?>)['sentenceIndex']! as int,
  ];

  http.Response _startLiveCheck(Map<String, Object?> body) {
    final prompt = body['prompt']! as String;
    if (findPersonalInfo(prompt).isNotEmpty) {
      return _json({
        'status': 'blocked',
        'reasons': ['personal_info'],
        'message': '電話番号のような個人情報が入っているみたい。',
      });
    }
    final answer = liveCheckAnswer;
    if (answer == null) {
      return errorResponse(503, 'upstream_unavailable');
    }
    if (prompt.contains(offTopicWord)) {
      return _json({
        'status': 'blocked',
        'reasons': ['off_topic'],
        'message': 'この問題のテーマとちがう質問みたい。',
      });
    }
    final sessionId = 'session${liveCheckSessions.length + 1}';
    liveCheckSessions[sessionId] = (
      exerciseId: body['exerciseId']! as String,
      lookupsUsed: 0,
      answered: false,
    );
    return _json({
      'status': 'generated',
      'sessionId': sessionId,
      'sentences': [
        for (final (i, text) in answer.sentences.indexed)
          {'index': i, 'text': text},
      ],
      'errorCount': answer.errors.length,
      'lookupsLeft': liveCheckLookupLimit,
    });
  }

  http.Response _lookup(String sessionId, Map<String, Object?> body) {
    final session = liveCheckSessions[sessionId];
    final answer = liveCheckAnswer;
    if (session == null || answer == null) {
      return errorResponse(404, 'not_found');
    }
    final left = liveCheckLookupLimit - session.lookupsUsed;
    if (session.answered || left <= 0) {
      return errorResponse(409, 'conflict');
    }
    liveCheckSessions[sessionId] = (
      exerciseId: session.exerciseId,
      lookupsUsed: session.lookupsUsed + 1,
      answered: false,
    );
    final index = body['sentenceIndex']! as int;
    return _json({
      'sentenceIndex': index,
      'sources': answer.sources[index] ?? const [],
      'lookupsLeft': left - 1,
    });
  }

  http.Response _answerLiveCheck(
    String exerciseId,
    Map<String, Object?> answer,
  ) {
    final sessionId = answer['sessionId']! as String;
    final session = liveCheckSessions[sessionId];
    final live = liveCheckAnswer;
    if (session == null || live == null) {
      return errorResponse(404, 'not_found');
    }
    if (session.exerciseId != exerciseId) {
      return errorResponse(400, 'bad_request');
    }
    if (session.answered) {
      return errorResponse(409, 'conflict');
    }
    liveCheckSessions[sessionId] = (
      exerciseId: exerciseId,
      lookupsUsed: session.lookupsUsed,
      answered: true,
    );
    final (correct, graded) = _hallucination(answer, {'errors': live.errors});
    attempted.add(exerciseId);
    final gained = correct && _correctOnce.add(exerciseId) ? 10 : 0;
    xp += gained;
    return _json({
      'attemptId': 'attempt${requests.length}',
      'correct': correct,
      'result': {
        ...graded,
        'type': 'live_check',
        'sources': [
          for (final index in live.sources.keys.toList()..sort())
            ...live.sources[index]!,
        ],
      },
      'progress': {'xp': xp, 'xpGained': gained, 'streakDays': streakDays},
    });
  }

  /// Like the server: correct for the best option; the result carries the
  /// chosen option's outcome scenes.
  static (bool, Map<String, Object?>) _story(
    Map<String, Object?> answer,
    Map<String, Object?> key,
  ) {
    final optionId = answer['optionId'];
    final outcome = [
      for (final o in key['outcomes']! as List)
        if ((o as Map<String, Object?>)['optionId'] == optionId) o,
    ].single;
    return (
      optionId == key['bestOptionId'],
      {
        'type': 'story',
        'bestOptionId': key['bestOptionId'],
        'outcome': outcome['scenes'],
        'explanation': key['explanation'],
      },
    );
  }

  static bool _sameMap(Object? a, Object? b) =>
      a is Map &&
      b is Map &&
      a.length == b.length &&
      a.entries.every((e) => b[e.key] == e.value);

  static http.Response _json(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// The fake AI's answer to a live check: [sentences] as the learner sees
/// them (already rewritten), the rewritten ones as `HallucinationError` JSON
/// and the `WebSource` JSON per sentence index.
class FakeLiveCheckAnswer {
  const FakeLiveCheckAnswer({
    required this.sentences,
    required this.errors,
    required this.sources,
  });

  final List<String> sentences;
  final List<Map<String, Object?>> errors;
  final Map<int, List<Map<String, Object?>>> sources;
}
