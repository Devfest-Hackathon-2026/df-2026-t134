import 'dart:convert';

import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../models/prompt_evaluation_test.dart' show blockedJson, evaluatedJson;
import 'api_client_test.dart' show clientReturning;

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  group('evaluatePrompt', () {
    test('posts the request with the ID token and parses evaluated', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        jsonResponse(evaluatedJson()),
        calls: calls,
      );

      final response = await client.evaluatePrompt(
        exerciseId: 'u2-l1-q6',
        prompt: '家族で出かける場所を 3 つ、箇条書きで',
      );

      final request = calls.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/base/v1/prompt/evaluate');
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'exerciseId': 'u2-l1-q6',
        'prompt': '家族で出かける場所を 3 つ、箇条書きで',
      });
      expect((response as PromptEvaluated).total, 7);
    });

    test('a blocked prompt is a normal result', () async {
      final client = clientReturning(jsonResponse(blockedJson()));

      final response = await client.evaluatePrompt(
        exerciseId: 'u2-l1-q6',
        prompt: '090-1234-5678 に電話して',
      );

      expect(
        (response as PromptBlocked).reasons,
        contains(PromptBlockReason.personalInfo),
      );
    });

    for (final (status, wire, code) in [
      (503, 'upstream_unavailable', ApiErrorCode.upstreamUnavailable),
      (429, 'rate_limited', ApiErrorCode.rateLimited),
      (400, 'bad_request', ApiErrorCode.badRequest),
    ]) {
      test('a $status $wire keeps its code', () {
        final client = clientReturning(
          jsonResponse({
            'error': {'code': wire, 'message': 'no'},
          }, status),
        );

        expect(
          client.evaluatePrompt(exerciseId: 'u2-l1-q6', prompt: 'ok'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.code, 'code', code)
                .having((e) => e.path, 'path', '/v1/prompt/evaluate'),
          ),
        );
      });
    }

    test('a malformed body is a FormatException', () {
      final client = clientReturning(jsonResponse({'status': 'graded'}));

      expect(
        client.evaluatePrompt(exerciseId: 'u2-l1-q6', prompt: 'ok'),
        throwsFormatException,
      );
    });

    test('an untrimmed prompt is rejected before sending', () async {
      final calls = <http.Request>[];
      final client = clientReturning(
        jsonResponse(evaluatedJson()),
        calls: calls,
      );

      await expectLater(
        client.evaluatePrompt(exerciseId: 'u2-l1-q6', prompt: ' ok '),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });
  });
}
