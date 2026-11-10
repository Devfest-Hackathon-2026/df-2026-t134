import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> evaluatedJson() => {
  'status': 'evaluated',
  'attemptId': 'a1b2',
  'total': 7,
  'scores': {
    'purpose': 2,
    'context': 1,
    'constraints': 2,
    'format': 1,
    'safety': 1,
  },
  'goodPoint': '目的がはっきりしているね。',
  'improvements': ['人数を書こう', '予算を書こう'],
  'hint': '形を決めよう',
  'progress': {'xp': 30, 'xpGained': 10, 'streakDays': 2},
};

Map<String, Object?> blockedJson() => {
  'status': 'blocked',
  'reasons': ['personal_info', 'off_topic'],
  'message': '電話番号のような個人情報が入っているみたい。',
};

void main() {
  group('PromptEvaluationResponse', () {
    test('parses an evaluated prompt', () {
      final response = PromptEvaluationResponse.fromJson(evaluatedJson());

      expect(response, isA<PromptEvaluated>());
      response as PromptEvaluated;
      expect(response.attemptId, 'a1b2');
      expect(response.total, 7);
      expect(response.passed, isTrue);
      expect(response.scores.of(RubricAxis.purpose), 2);
      expect(response.scores.of(RubricAxis.context), 1);
      expect(response.scores.of(RubricAxis.constraints), 2);
      expect(response.scores.of(RubricAxis.format), 1);
      expect(response.scores.of(RubricAxis.safety), 1);
      expect(response.goodPoint, '目的がはっきりしているね。');
      expect(response.improvements, ['人数を書こう', '予算を書こう']);
      expect(response.hint, '形を決めよう');
      expect(response.progress.xpGained, 10);
    });

    test('a total under 6 does not pass', () {
      final json = evaluatedJson()..['total'] = 5;

      expect((PromptEvaluated.fromJson(json)).passed, isFalse);
    });

    test('parses a blocked prompt', () {
      final response = PromptEvaluationResponse.fromJson(blockedJson());

      expect(response, isA<PromptBlocked>());
      response as PromptBlocked;
      expect(response.reasons, [
        PromptBlockReason.personalInfo,
        PromptBlockReason.offTopic,
      ]);
      expect(response.message, startsWith('電話番号'));
    });

    test('rejects documents outside the contract', () {
      final broken = <Map<String, Object?>>[
        {...evaluatedJson(), 'status': 'graded'},
        {...evaluatedJson(), 'total': 11},
        {...evaluatedJson(), 'extra': true},
        {...evaluatedJson(), 'improvements': <String>[]},
        {
          ...evaluatedJson(),
          'improvements': ['a', 'b', 'c'],
        },
        {
          ...evaluatedJson(),
          'improvements': [1],
        },
        {
          ...evaluatedJson(),
          'scores': {
            'purpose': 3,
            'context': 1,
            'constraints': 2,
            'format': 1,
            'safety': 1,
          },
        },
        {
          ...evaluatedJson(),
          'scores': {'purpose': 2},
        },
        {...evaluatedJson(), 'attemptId': 'Not An Id'},
        {...blockedJson(), 'reasons': <String>[]},
        {
          ...blockedJson(),
          'reasons': ['too_long'],
        },
        {...blockedJson(), 'message': null},
      ];
      for (final json in broken) {
        expect(
          () => PromptEvaluationResponse.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
      expect(
        () => PromptEvaluationResponse.fromJson('evaluated'),
        throwsFormatException,
      );
    });
  });

  group('EvaluatePromptRequest', () {
    test('serializes to the contract', () {
      expect(
        EvaluatePromptRequest(
          exerciseId: 'u2-l1-q6',
          prompt: '家族で出かける場所を 3 つ',
        ).toJson(),
        {'exerciseId': 'u2-l1-q6', 'prompt': '家族で出かける場所を 3 つ'},
      );
    });

    test('rejects what the API would reject', () {
      for (final (id, prompt) in [
        ('u2-l1-q6', ''),
        ('u2-l1-q6', ' 前後に空白 '),
        ('u2-l1-q6', 'あ' * 1001),
        ('U2 L1', 'ok'),
      ]) {
        expect(
          () => EvaluatePromptRequest(exerciseId: id, prompt: prompt),
          throwsArgumentError,
          reason: '$id / ${prompt.length}',
        );
      }
      expect(
        EvaluatePromptRequest(
          exerciseId: 'u2-l1-q6',
          prompt: 'あ' * 1000,
        ).prompt,
        hasLength(1000),
      );
    });
  });

  test('promptLength counts code points like the API', () {
    expect(promptLength('abc'), 3);
    expect(promptLength('プロンプト'), 5);
    expect(promptLength('😀'), 1, reason: 'one code point, two UTF-16 units');
    expect(
      promptLength('👨‍👩‍👧'),
      5,
      reason: 'one grapheme, five code points',
    );
  });
}
