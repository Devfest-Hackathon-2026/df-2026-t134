import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:ailearn/models/live_check.dart';
import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> exerciseJson([Map<String, Object?> changes = const {}]) =>
    {
      'id': 'u3-l1-q3',
      'lessonId': 'u3-l1',
      'type': 'live_check',
      'question': 'AI に質問しよう',
      'theme': '富士山',
      'suggestions': ['富士山の高さは？'],
      'errorCount': 1,
      ...changes,
    };

Map<String, Object?> startedJson([Map<String, Object?> changes = const {}]) => {
  'status': 'generated',
  'sessionId': 'abc123',
  'sentences': [
    {'index': 0, 'text': '一文目。'},
    {'index': 1, 'text': '二文目。'},
    {'index': 2, 'text': '三文目。'},
  ],
  'errorCount': 1,
  'lookupsLeft': 2,
  ...changes,
};

Map<String, Object?> resultJson([Map<String, Object?> changes = const {}]) => {
  'type': 'live_check',
  'errors': [
    {'index': 1, 'errorType': 'number', 'correction': '正しい文。', 'tip': 'コツ'},
  ],
  'found': [1],
  'missed': <int>[],
  'falseAlarms': [0],
  'sources': [
    {'title': 'example.jp', 'uri': 'https://example.jp/a'},
  ],
  ...changes,
};

void main() {
  group('LiveCheckExercise', () {
    test('parses the contract with its defaults', () {
      final exercise = Exercise.fromJson(exerciseJson()) as LiveCheckExercise;

      expect(exercise.type, ExerciseType.liveCheck);
      expect(exercise.theme, '富士山');
      expect(exercise.suggestions, ['富士山の高さは？']);
      expect(exercise.errorCount, 1);
      expect(exercise.lookupLimit, LiveCheckExercise.defaultLookupLimit);
      expect(exercise.maxLength, LiveCheckExercise.defaultMaxLength);
    });

    for (final (name, changes) in [
      ('three errors', {'errorCount': 3}),
      ('no suggestions', {'suggestions': <String>[]}),
      (
        'five suggestions',
        {
          'suggestions': ['a', 'b', 'c', 'd', 'e'],
        },
      ),
      ('six lookups', {'lookupLimit': 6}),
      ('too long prompts', {'maxLength': 401}),
      ('an unknown field', {'answer': 'x'}),
      ('a blank theme', {'theme': ''}),
    ]) {
      test('rejects $name', () {
        expect(
          () => Exercise.fromJson(exerciseJson(changes)),
          throwsFormatException,
        );
      });
    }
  });

  group('StartLiveCheckResponse', () {
    test('generated has the sentences and the counts', () {
      final started =
          StartLiveCheckResponse.fromJson(startedJson()) as LiveCheckStarted;

      expect(started.sessionId, 'abc123');
      expect(
        [for (final s in started.sentences) s.text],
        ['一文目。', '二文目。', '三文目。'],
      );
      expect((started.errorCount, started.lookupsLeft), (1, 2));
    });

    test('blocked has the reasons and the message', () {
      final blocked = StartLiveCheckResponse.fromJson({
        'status': 'blocked',
        'reasons': ['off_topic'],
        'message': 'テーマとちがうみたい',
      }) as LiveCheckBlocked;

      expect(blocked.reasons, [PromptBlockReason.offTopic]);
      expect(blocked.message, 'テーマとちがうみたい');
    });

    for (final (name, json) in [
      ('an unknown status', startedJson({'status': 'graded'})),
      ('an unknown field', startedJson({'errors': <Object>[]})),
      (
        'one sentence',
        startedJson({
          'sentences': [
            {'index': 0, 'text': 'a'},
          ],
        }),
      ),
      (
        'unordered indexes',
        startedJson({
          'sentences': [
            {'index': 1, 'text': 'a'},
            {'index': 0, 'text': 'b'},
          ],
        }),
      ),
      (
        'as many errors as sentences',
        startedJson({
          'errorCount': 2,
          'sentences': [
            {'index': 0, 'text': 'a'},
            {'index': 1, 'text': 'b'},
          ],
        }),
      ),
      ('a negative lookup count', startedJson({'lookupsLeft': -1})),
      ('a session id that is not an id', startedJson({'sessionId': 'A B'})),
      (
        'blocked without reasons',
        {'status': 'blocked', 'reasons': <String>[], 'message': ''},
      ),
    ]) {
      test('rejects $name', () {
        expect(
          () => StartLiveCheckResponse.fromJson(json),
          throwsFormatException,
        );
      });
    }
  });

  group('lookup', () {
    test('the request carries the index; the response the sources', () {
      expect(LookupRequest(2).toJson(), {'sentenceIndex': 2});
      expect(() => LookupRequest(-1), throwsArgumentError);

      final response = LookupResponse.fromJson({
        'sentenceIndex': 2,
        'sources': [
          {'title': 'example.jp', 'uri': 'https://example.jp/a'},
        ],
        'lookupsLeft': 0,
      });

      expect(response.sources, [
        const WebSource(title: 'example.jp', uri: 'https://example.jp/a'),
      ]);
      expect(response.lookupsLeft, 0);
    });

    test('a source without an address is malformed', () {
      expect(
        () => WebSource.fromJson({'title': 'x', 'uri': ''}),
        throwsFormatException,
      );
      expect(
        () => WebSource.fromJson({'title': 'x', 'uri': 'u', 'snippet': 's'}),
        throwsFormatException,
      );
    });
  });

  group('answer and result', () {
    test('the answer names the session and the marked sentences', () {
      final answer = LiveCheckAnswer(sessionId: 'abc123', sentenceIndexes: [0]);

      expect(answer.toJson(), {
        'type': 'live_check',
        'sessionId': 'abc123',
        'sentenceIndexes': [0],
      });
      expect(
        () => LiveCheckAnswer(sessionId: 'not an id', sentenceIndexes: [0]),
        throwsArgumentError,
      );
    });

    test('the result has the verdicts, corrections and sources', () {
      final result = AnswerResult.fromJson(resultJson()) as LiveCheckResult;

      expect(result.type, ExerciseType.liveCheck);
      expect(result.errors.single.correction, '正しい文。');
      expect(result.found, [1]);
      expect(result.missed, isEmpty);
      expect(result.falseAlarms, [0]);
      expect(result.sources.single.title, 'example.jp');
      expect(result.asHallucination.errors, result.errors);
    });

    test('a result with unknown fields or without sources is malformed', () {
      expect(
        () => AnswerResult.fromJson(resultJson({'explanation': 'x'})),
        throwsFormatException,
      );
      expect(
        () => AnswerResult.fromJson({...resultJson()}..remove('sources')),
        throwsFormatException,
      );
    });
  });
}
