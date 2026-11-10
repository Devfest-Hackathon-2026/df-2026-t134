import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> progressJson() => {
  'xp': 40,
  'xpGained': 10,
  'streakDays': 3,
};

Map<String, Object?> responseJson(Map<String, Object?> result) => {
  'attemptId': '0123abcd',
  'correct': true,
  'result': result,
  'progress': progressJson(),
};

void main() {
  group('SubmitAnswerRequest.toJson', () {
    test('matches the contract for every answer type', () {
      expect(
        const SubmitAnswerRequest(
          exerciseId: 'u1-l1-q1',
          answer: ChoiceAnswer('b'),
        ).toJson(),
        {
          'exerciseId': 'u1-l1-q1',
          'answer': {'type': 'choice', 'optionId': 'b'},
        },
      );
      expect(OrderAnswer(['input', 'predict']).toJson(), {
        'type': 'order',
        'itemIds': ['input', 'predict'],
      });
      expect(FillBlankAnswer({'data': 'a', 'pattern': 'b'}).toJson(), {
        'type': 'fill_blank',
        'selectedOptions': {'data': 'a', 'pattern': 'b'},
      });
      expect(HallucinationAnswer([1, 3]).toJson(), {
        'type': 'hallucination',
        'sentenceIndexes': [1, 3],
      });
    });
  });

  group('SubmitAnswerResponse.fromJson', () {
    test('parses a choice result', () {
      final response = SubmitAnswerResponse.fromJson(
        responseJson({
          'type': 'choice',
          'correctOptionId': 'b',
          'explanation': '1 行目\n2 行目',
        }),
      );

      expect(response.attemptId, '0123abcd');
      expect(response.correct, isTrue);
      expect(response.progress.xp, 40);
      expect(response.progress.xpGained, 10);
      expect(response.progress.streakDays, 3);
      final result = response.result as ChoiceResult;
      expect(result.type, ExerciseType.choice);
      expect(result.correctOptionId, 'b');
      expect(result.explanation, '1 行目\n2 行目');
    });

    test('parses order, fill_blank and hallucination results', () {
      final order =
          SubmitAnswerResponse.fromJson(
                responseJson({
                  'type': 'order',
                  'correctOrder': ['input', 'predict'],
                  'explanation': '',
                }),
              ).result
              as OrderResult;
      expect(order.correctOrder, ['input', 'predict']);
      expect(order.explanation, isEmpty);

      final fill =
          SubmitAnswerResponse.fromJson(
                responseJson({
                  'type': 'fill_blank',
                  'correctOptions': {'next': 'b'},
                  'explanation': 'なるほど',
                }),
              ).result
              as FillBlankResult;
      expect(fill.correctOptions, {'next': 'b'});

      final hallucination =
          SubmitAnswerResponse.fromJson(
                responseJson({
                  'type': 'hallucination',
                  'errors': [
                    {
                      'index': 1,
                      'errorType': 'fake_source',
                      'correction': '正しくは葉です',
                      'tip': '教科書で確かめよう',
                    },
                  ],
                  'found': [1],
                  'missed': <int>[],
                  'falseAlarms': [0],
                }),
              ).result
              as HallucinationResult;
      expect(
        hallucination.errors.single.errorType,
        HallucinationErrorType.fakeSource,
      );
      expect(hallucination.found, [1]);
      expect(hallucination.missed, isEmpty);
      expect(hallucination.falseAlarms, [0]);
    });

    test('rejects unknown types, unknown fields and bad values', () {
      final choice = {
        'type': 'choice',
        'correctOptionId': 'b',
        'explanation': 'x',
      };
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson({...choice, 'type': 'prompt'}),
        ),
        throwsFormatException,
      );
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson({...choice, 'score': 3}),
        ),
        throwsFormatException,
      );
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson(choice)..['extra'] = true,
        ),
        throwsFormatException,
      );
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson(choice)..['correct'] = 'yes',
        ),
        throwsFormatException,
      );
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson(choice)
            ..['progress'] = {...progressJson(), 'xpGained': -1},
        ),
        throwsFormatException,
      );
      expect(
        () => SubmitAnswerResponse.fromJson(
          responseJson({
            'type': 'hallucination',
            'errors': [
              {'index': 1, 'errorType': 'rumor', 'correction': 'a', 'tip': 'b'},
            ],
            'found': <int>[],
            'missed': <int>[],
            'falseAlarms': <int>[],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  test('CompleteLessonResponse.fromJson parses and rejects unknown fields', () {
    final response = CompleteLessonResponse.fromJson({
      'lessonId': 'u1-l1',
      'progress': progressJson(),
    });

    expect(response.lessonId, 'u1-l1');
    expect(response.progress.xp, 40);
    expect(
      () => CompleteLessonResponse.fromJson({
        'lessonId': 'u1-l1',
        'progress': progressJson(),
        'bonus': 20,
      }),
      throwsFormatException,
    );
  });
}
