import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/answer.dart';
import '../models/health_status.dart';
import '../models/json_fields.dart';
import '../models/live_check.dart';
import '../models/prompt_evaluation.dart';

/// `error.code` of the API's ErrorResponse (docs/openapi.json `ErrorBody`).
/// Branch on this, never on the message.
enum ApiErrorCode {
  badRequest('bad_request'),
  unauthenticated('unauthenticated'),
  forbidden('forbidden'),
  notFound('not_found'),
  conflict('conflict'),
  rateLimited('rate_limited'),
  notImplemented('not_implemented'),
  upstreamUnavailable('upstream_unavailable'),
  internal('internal');

  const ApiErrorCode(this.wireName);

  final String wireName;

  static ApiErrorCode? _fromWire(Object? value) {
    for (final code in values) {
      if (code.wireName == value) {
        return code;
      }
    }
    return null;
  }
}

/// Thrown when the API answers with a non-success status code.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.path,
    required this.code,
    this.message,
  });

  /// Reads `{"error": {"code", "message"}}` from [body]. [code] stays null
  /// when the body is not an ErrorResponse (e.g. a proxy's HTML error page).
  factory ApiException.fromResponse(int statusCode, String path, String body) {
    Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      json = null;
    }
    if (json case {
      'error': {'code': final Object code, 'message': final String message},
    }) {
      return ApiException(
        statusCode: statusCode,
        path: path,
        code: ApiErrorCode._fromWire(code),
        message: message,
      );
    }
    return ApiException(statusCode: statusCode, path: path, code: null);
  }

  final int statusCode;
  final String path;
  final ApiErrorCode? code;

  /// For logs only; it is not meant for learners.
  final String? message;

  /// Worth trying again later (server side or temporary problems).
  bool get isTemporary =>
      statusCode >= 500 ||
      code == ApiErrorCode.rateLimited ||
      code == ApiErrorCode.upstreamUnavailable;

  @override
  String toString() =>
      'ApiException($statusCode, $path, ${code?.wireName ?? 'no code'})';
}

/// Returns the Firebase ID token of the signed-in user.
typedef IdTokenProvider = Future<String> Function();

/// Returns the App Check token to send as `X-Firebase-AppCheck`, or null when
/// App Check is not used (the local emulators).
typedef AppCheckTokenProvider = Future<String?> Function();

/// [AppCheckTokenProvider] for the emulators and tests.
Future<String?> noAppCheckToken() async => null;

/// Thin wrapper around the learning API. All HTTP calls go through here.
///
/// Every `/v1` call except the health check sends
/// `Authorization: Bearer <ID token>` from [IdTokenProvider], and
/// `X-Firebase-AppCheck` when [AppCheckTokenProvider] returns a token.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    required this._httpClient,
    required this._idToken,
    required this._appCheckToken,
  });

  final Uri _baseUrl;
  final http.Client _httpClient;
  final IdTokenProvider _idToken;
  final AppCheckTokenProvider _appCheckToken;

  Future<HealthStatus> fetchHealth() async {
    const path = '/v1/health';
    final response = await _httpClient.get(_endpoint(path));
    return HealthStatus.fromJson(_decode(response, path));
  }

  /// `POST /v1/answers`. Throws [FormatException] when the result is for a
  /// different exercise type than the answer.
  Future<SubmitAnswerResponse> submitAnswer(SubmitAnswerRequest request) async {
    final response = SubmitAnswerResponse.fromJson(
      await postJson('/v1/answers', request.toJson()),
    );
    if (response.result.type != request.answer.type) {
      throw FormatException(
        'Result type ${response.result.type.wireName} does not match the '
        'answer type ${request.answer.type.wireName}',
      );
    }
    return response;
  }

  /// `POST /v1/lessons/{lessonId}/complete`. A 409 [ApiErrorCode.conflict]
  /// means some exercise of the lesson has no attempt yet.
  Future<CompleteLessonResponse> completeLesson(String lessonId) async {
    if (!isContractId(lessonId)) {
      throw ArgumentError.value(lessonId, 'lessonId', 'must be a contract id');
    }
    final path = '/v1/lessons/$lessonId/complete';
    final response = CompleteLessonResponse.fromJson(
      _decode(await _authenticatedPost(path, body: null), path),
    );
    if (response.lessonId != lessonId) {
      throw FormatException('Completed a different lesson', response.lessonId);
    }
    return response;
  }

  /// `POST /v1/prompt/evaluate`. [prompt] must be trimmed and non-empty.
  /// A `blocked` answer is a normal result; AI grading being off or the daily
  /// limit come as [ApiException] with [ApiErrorCode.upstreamUnavailable] or
  /// [ApiErrorCode.rateLimited].
  Future<PromptEvaluationResponse> evaluatePrompt({
    required String exerciseId,
    required String prompt,
  }) async {
    final request = EvaluatePromptRequest(
      exerciseId: exerciseId,
      prompt: prompt,
    );
    return PromptEvaluationResponse.fromJson(
      await postJson('/v1/prompt/evaluate', request.toJson()),
    );
  }

  /// `POST /v1/live-checks`. [prompt] must be trimmed and non-empty. A
  /// `blocked` answer is a normal result; AI being off and the daily limit
  /// come as [ApiException] with [ApiErrorCode.upstreamUnavailable] or
  /// [ApiErrorCode.rateLimited].
  Future<StartLiveCheckResponse> startLiveCheck({
    required String exerciseId,
    required String prompt,
  }) async {
    final request = StartLiveCheckRequest(
      exerciseId: exerciseId,
      prompt: prompt,
    );
    return StartLiveCheckResponse.fromJson(
      await postJson('/v1/live-checks', request.toJson()),
    );
  }

  /// `POST /v1/live-checks/{sessionId}/lookup`. A 409
  /// [ApiErrorCode.conflict] means no lookups are left (or the session was
  /// answered). Throws [FormatException] when the sources are for another
  /// sentence.
  Future<LookupResponse> lookupLiveCheck({
    required String sessionId,
    required int sentenceIndex,
  }) async {
    if (!isContractId(sessionId)) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'must be a contract id',
      );
    }
    final response = LookupResponse.fromJson(
      await postJson(
        '/v1/live-checks/$sessionId/lookup',
        LookupRequest(sentenceIndex).toJson(),
      ),
    );
    if (response.sentenceIndex != sentenceIndex) {
      throw FormatException('Sources for another sentence', response);
    }
    return response;
  }

  /// POSTs [body] as JSON to an authenticated endpoint and returns the decoded
  /// response. The typed methods above wrap this.
  Future<Object?> postJson(String path, Object? body) async {
    final response = await _authenticatedPost(path, body: jsonEncode(body));
    return _decode(response, path);
  }

  /// [body] null sends no body (endpoints without a request body).
  Future<http.Response> _authenticatedPost(
    String path, {
    required String? body,
  }) async {
    if (!path.startsWith('/v1/') || path == '/v1/health') {
      throw ArgumentError.value(
        path,
        'path',
        'must be an authenticated /v1 path',
      );
    }
    final token = await _idToken();
    final appCheckToken = await _appCheckToken();
    return _httpClient.post(
      _endpoint(path),
      headers: {
        'Authorization': 'Bearer $token',
        'X-Firebase-AppCheck': ?appCheckToken,
        if (body != null) 'Content-Type': 'application/json',
      },
      body: body,
    );
  }

  Object? _decode(http.Response response, String path) {
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(
        response.statusCode,
        path,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Uri _endpoint(String path) => _baseUrl.replace(path: '${_baseUrl.path}$path');
}
