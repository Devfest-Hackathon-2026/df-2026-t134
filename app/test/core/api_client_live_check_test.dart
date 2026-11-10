import 'dart:convert';

import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/live_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../models/live_check_test.dart' show resultJson, startedJson;
import 'api_client_prompt_test.dart' show jsonResponse;
import 'api_client_test.dart' show clientReturning;

void main() {
  group('startLiveCheck', () {
    test('posts the prompt with the ID token and parses the answer', () async {
      final calls = <http.Request>[];
      final client = clientReturning(jsonResponse(startedJson()), calls: calls);

      final response = await client.startLiveCheck(
        exerciseId: 'u3-l1-q3',
        prompt: '富士山の高さは？',
      );

      final request = calls.single;
      expect(request.url.path, '/base/v1/live-checks');
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(jsonDecode(request.body), {
        'exerciseId': 'u3-l1-q3',
        'prompt': '富士山の高さは？',
      });
      expect((response as LiveCheckStarted).sessionId, 'abc123');
    });

    for (final (status, wire, code) in [
      (503, 'upstream_unavailable', ApiErrorCode.upstreamUnavailable),
      (429, 'rate_limited', ApiErrorCode.rateLimited),
    ]) {
      test('a $status keeps its code', () {
        final client = clientReturning(
          jsonResponse({
            'error': {'code': wire, 'message': 'no'},
          }, status),
        );

        expect(
          client.startLiveCheck(exerciseId: 'u3-l1-q3', prompt: 'ok'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
      });
    }

    test(
      'a blank, untrimmed or too long prompt is rejected before sending',
      () {
        final calls = <http.Request>[];
        final client = clientReturning(
          jsonResponse(startedJson()),
          calls: calls,
        );

        for (final prompt in [
          '',
          ' ok',
          'あ' * (maxLiveCheckPromptLength + 1),
        ]) {
          expect(
            () => client.startLiveCheck(exerciseId: 'u3-l1-q3', prompt: prompt),
            throwsArgumentError,
          );
        }
        expect(calls, isEmpty);
      },
    );
  });

  group('lookupLiveCheck', () {
    test('posts the sentence index under the session', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        jsonResponse({
          'sentenceIndex': 1,
          'sources': <Object>[],
          'lookupsLeft': 1,
        }),
        calls: calls,
      );

      final response = await client.lookupLiveCheck(
        sessionId: 'abc123',
        sentenceIndex: 1,
      );

      expect(calls.single.url.path, '/base/v1/live-checks/abc123/lookup');
      expect(jsonDecode(calls.single.body), {'sentenceIndex': 1});
      expect(response.lookupsLeft, 1);
    });

    test('sources of another sentence are malformed', () {
      final client = clientReturning(
        jsonResponse({
          'sentenceIndex': 2,
          'sources': <Object>[],
          'lookupsLeft': 1,
        }),
      );

      expect(
        client.lookupLiveCheck(sessionId: 'abc123', sentenceIndex: 1),
        throwsFormatException,
      );
    });

    test('a session id that is not an id never becomes a path', () {
      final calls = <http.Request>[];
      final client = clientReturning(jsonResponse({}), calls: calls);

      expect(
        () => client.lookupLiveCheck(sessionId: '../x', sentenceIndex: 0),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('409 conflict keeps its code', () {
      final client = clientReturning(
        jsonResponse({
          'error': {'code': 'conflict', 'message': 'none left'},
        }, 409),
      );

      expect(
        client.lookupLiveCheck(sessionId: 'abc123', sentenceIndex: 0),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.conflict,
          ),
        ),
      );
    });
  });

  test('a live check answer gets a live check result', () async {
    final client = clientReturning(
      jsonResponse({
        'attemptId': 'a1',
        'correct': false,
        'result': resultJson(),
        'progress': {'xp': 0, 'xpGained': 0, 'streakDays': 0},
      }),
    );

    final response = await client.submitAnswer(
      SubmitAnswerRequest(
        exerciseId: 'u3-l1-q3',
        answer: LiveCheckAnswer(sessionId: 'abc123', sentenceIndexes: [0, 1]),
      ),
    );

    expect(response.result, isA<LiveCheckResult>());
  });
}
