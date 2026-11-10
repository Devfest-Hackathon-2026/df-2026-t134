import 'dart:convert';

import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/models/answer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient clientReturning(
  http.Response response, {
  List<http.Request>? calls,
  IdTokenProvider? idToken,
  AppCheckTokenProvider? appCheckToken,
}) {
  return ApiClient(
    baseUrl: Uri.parse('https://api.example.com/base'),
    httpClient: MockClient((request) async {
      calls?.add(request);
      return response;
    }),
    idToken: idToken ?? () async => 'id-token',
    appCheckToken: appCheckToken ?? noAppCheckToken,
  );
}

void main() {
  test('fetchHealth calls /v1/health under the base path', () async {
    final calls = <http.Request>[];
    final client = clientReturning(
      http.Response('{"status":"ok","version":"0.1.0","env":"local"}', 200),
      calls: calls,
    );

    final health = await client.fetchHealth();

    expect(
      calls.single.url.toString(),
      'https://api.example.com/base/v1/health',
    );
    expect(health.version, '0.1.0');
    expect(health.env, 'local');
  });

  test('fetchHealth does not ask for or send an ID token', () async {
    final calls = <http.Request>[];
    final client = clientReturning(
      http.Response('{"status":"ok","version":"0.1.0","env":"local"}', 200),
      calls: calls,
      idToken: () => fail('health must not need a token'),
    );

    await client.fetchHealth();

    expect(calls.single.headers.containsKey('Authorization'), isFalse);
  });

  test('fetchHealth throws ApiException on non-200', () {
    final client = clientReturning(http.Response('down', 503));

    expect(client.fetchHealth(), throwsA(isA<ApiException>()));
  });

  test('fetchHealth throws FormatException on an unexpected body', () {
    final client = clientReturning(http.Response('{"status":"ng"}', 200));

    expect(client.fetchHealth(), throwsFormatException);
  });

  test('postJson sends the ID token as a Bearer token and JSON body', () async {
    final calls = <http.Request>[];
    final client = clientReturning(
      http.Response('{"ok":true}', 200),
      calls: calls,
      idToken: () async => 'abc.def',
    );

    final result = await client.postJson('/v1/answers', {'a': 1});

    final request = calls.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.example.com/base/v1/answers');
    expect(request.headers['Authorization'], 'Bearer abc.def');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(request.body, '{"a":1}');
    expect(result, {'ok': true});
  });

  test('postJson throws ApiException on 401', () {
    final client = clientReturning(http.Response('{}', 401));

    expect(
      client.postJson('/v1/answers', {}),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
  });

  test('postJson rejects paths outside the authenticated API', () {
    final client = clientReturning(http.Response('{}', 200));

    expect(() => client.postJson('/v1/health', {}), throwsArgumentError);
    expect(() => client.postJson('/other', {}), throwsArgumentError);
  });

  test('postJson fails when there is no signed-in user', () {
    final client = clientReturning(
      http.Response('{}', 200),
      idToken: () async => throw StateError('signed out'),
    );

    expect(client.postJson('/v1/answers', {}), throwsStateError);
  });

  group('submitAnswer', () {
    const choiceResponse =
        '{"attemptId":"a1","correct":false,'
        '"result":{"type":"choice","correctOptionId":"b",'
        '"explanation":"せつめい\\n2 行目"},'
        '"progress":{"xp":0,"xpGained":0,"streakDays":0}}';

    test('posts the typed request and parses the typed response', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        http.Response.bytes(utf8.encode(choiceResponse), 200),
        calls: calls,
      );

      final response = await client.submitAnswer(
        const SubmitAnswerRequest(
          exerciseId: 'u1-l1-q1',
          answer: ChoiceAnswer('a'),
        ),
      );

      final request = calls.single;
      expect(request.url.path, '/base/v1/answers');
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(jsonDecode(request.body), {
        'exerciseId': 'u1-l1-q1',
        'answer': {'type': 'choice', 'optionId': 'a'},
      });
      expect(response.correct, isFalse);
      final result = response.result as ChoiceResult;
      expect(result.correctOptionId, 'b');
      expect(result.explanation, 'せつめい\n2 行目');
    });

    test('rejects a result of another exercise type', () {
      final client = clientReturning(
        http.Response.bytes(utf8.encode(choiceResponse), 200),
      );

      expect(
        client.submitAnswer(
          SubmitAnswerRequest(
            exerciseId: 'u1-l1-q4',
            answer: OrderAnswer(['a', 'b']),
          ),
        ),
        throwsFormatException,
      );
    });

    test('turns the error body into an ApiException with its code', () {
      final client = clientReturning(
        http.Response(
          '{"error":{"code":"bad_request","message":"unknown option"}}',
          400,
        ),
      );

      expect(
        client.submitAnswer(
          const SubmitAnswerRequest(
            exerciseId: 'u1-l1-q1',
            answer: ChoiceAnswer('z'),
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', ApiErrorCode.badRequest)
              .having((e) => e.message, 'message', 'unknown option')
              .having((e) => e.isTemporary, 'isTemporary', isFalse),
        ),
      );
    });
  });

  group('completeLesson', () {
    test('posts without a body and parses the progress', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        http.Response(
          '{"lessonId":"u1-l1",'
          '"progress":{"xp":80,"xpGained":20,"streakDays":2}}',
          200,
        ),
        calls: calls,
      );

      final response = await client.completeLesson('u1-l1');

      final request = calls.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/base/v1/lessons/u1-l1/complete');
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(request.body, isEmpty);
      expect(response.lessonId, 'u1-l1');
      expect(response.progress.xp, 80);
      expect(response.progress.xpGained, 20);
      expect(response.progress.streakDays, 2);
    });

    test('a 409 conflict keeps its code', () {
      final client = clientReturning(
        http.Response(
          '{"error":{"code":"conflict","message":"not every exercise"}}',
          409,
        ),
      );

      expect(
        client.completeLesson('u1-l1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.code, 'code', ApiErrorCode.conflict),
        ),
      );
    });

    test('a non-JSON error body gives no code and counts as temporary', () {
      final client = clientReturning(http.Response('<html>502</html>', 502));

      expect(
        client.completeLesson('u1-l1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', isNull)
              .having((e) => e.isTemporary, 'isTemporary', isTrue),
        ),
      );
    });

    test('an unknown error code gives no code', () {
      final client = clientReturning(
        http.Response('{"error":{"code":"teapot","message":"x"}}', 418),
      );

      expect(
        client.completeLesson('u1-l1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', isNull)),
      );
    });

    test('rejects ids that are not contract ids before sending', () {
      final calls = <http.Request>[];
      final client = clientReturning(http.Response('{}', 200), calls: calls);

      expect(() => client.completeLesson('../admin'), throwsArgumentError);
      expect(calls, isEmpty);
    });

    test('rejects a response for another lesson', () {
      final client = clientReturning(
        http.Response(
          '{"lessonId":"u1-l2",'
          '"progress":{"xp":0,"xpGained":0,"streakDays":0}}',
          200,
        ),
      );

      expect(client.completeLesson('u1-l1'), throwsFormatException);
    });
  });

  group('App Check header', () {
    const body = {'exerciseId': 'u1-l1-q1'};

    test('is sent when a token is available', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        http.Response('{}', 200),
        calls: calls,
        appCheckToken: () async => 'app-check-token',
      );

      await client.postJson('/v1/answers', body);

      expect(calls.single.headers['X-Firebase-AppCheck'], 'app-check-token');
      expect(calls.single.headers['Authorization'], 'Bearer id-token');
    });

    test('is omitted without App Check (emulators)', () async {
      final calls = <http.Request>[];
      final client = clientReturning(http.Response('{}', 200), calls: calls);

      await client.postJson('/v1/answers', body);

      expect(calls.single.headers.containsKey('X-Firebase-AppCheck'), isFalse);
    });

    test('is not sent with the public health check', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        http.Response('{"status":"ok","version":"0.1.0","env":"prod"}', 200),
        calls: calls,
        appCheckToken: () async => 'app-check-token',
      );

      await client.fetchHealth();

      expect(calls.single.headers.containsKey('X-Firebase-AppCheck'), isFalse);
    });
  });
}
