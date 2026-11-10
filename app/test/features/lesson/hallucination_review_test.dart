import 'dart:convert';

import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/features/lesson/lesson_controller.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/answer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/hallucination.dart';

const _number = HallucinationError(
  index: 1,
  errorType: HallucinationErrorType.number,
  correction: '高さは 3776 メートルです。',
  tip: '地図帳で確かめよう。',
);

const _source = HallucinationError(
  index: 4,
  errorType: HallucinationErrorType.fakeSource,
  correction: 'そんな資料はありません。',
  tip: '資料が本当にあるか調べよう。',
);

HallucinationResult result({
  List<HallucinationError> errors = const [_number, _source],
  List<int> found = const [4],
  List<int> missed = const [1],
  List<int> falseAlarms = const [0],
}) => HallucinationResult(
  errors: errors,
  found: found,
  missed: missed,
  falseAlarms: falseAlarms,
);

void main() {
  final exercise = hallucinationFixture.exercise;

  test('gives every sentence a verdict in reading order', () {
    final review = HallucinationReview.resolve(exercise, result());

    expect(review.sentences.map((s) => s.sentence.index), [0, 1, 2, 3, 4]);
    expect(review.sentences.map((s) => s.verdict), [
      SentenceVerdict.falseAlarm,
      SentenceVerdict.missed,
      SentenceVerdict.untouched,
      SentenceVerdict.untouched,
      SentenceVerdict.found,
    ]);
    expect(review.sentences.map((s) => s.error), [
      null,
      _number,
      null,
      null,
      _source,
    ]);
    expect(review.errorCount, 2);
    expect(review.foundCount, 1);
    expect(review.falseAlarms.map((s) => s.sentence.index), [0]);
  });

  test('a result that does not fit the exercise is rejected', () {
    void rejects(HallucinationResult r) => expect(
      () => HallucinationReview.resolve(exercise, r),
      throwsFormatException,
    );

    rejects(result(falseAlarms: [5]));
    rejects(result(found: [4, 4]));
    rejects(result(found: [], missed: [1]));
    rejects(result(found: [4, 1]));
    rejects(result(falseAlarms: [1]));
    rejects(result(found: [4, 2]));
    rejects(result(errors: [_number, _number]));
    rejects(
      result(
        errors: [
          _number,
          const HallucinationError(
            index: 7,
            errorType: HallucinationErrorType.fact,
            correction: 'c',
            tip: 't',
          ),
        ],
      ),
    );
  });

  test('resolves a response captured from the real API', () {
    // POST /v1/answers with sentenceIndexes [0, 4] for the fixture, against
    // the API and the Firestore / Auth emulators (PR-11 end-to-end check).
    final response = SubmitAnswerResponse.fromJson(jsonDecode(_capturedWrong));

    expect(response.correct, isFalse);
    final answer = describeCorrectAnswer(exercise, response.result);
    final review = (answer as CorrectHallucination).review;
    expect(review.sentences.map((s) => s.verdict), [
      SentenceVerdict.falseAlarm,
      SentenceVerdict.missed,
      SentenceVerdict.untouched,
      SentenceVerdict.untouched,
      SentenceVerdict.found,
    ]);
    expect(review.errors.map((s) => s.error!.errorType), [
      HallucinationErrorType.number,
      HallucinationErrorType.fakeSource,
    ]);
  });

  group('HallucinationDraft', () {
    test('toggles sentences and sends them sorted', () {
      final draft = HallucinationDraft(exercise).toggle(4).toggle(1);

      expect(draft.selectedIndexes, {1, 4});
      expect(draft.toAnswer()?.toJson(), {
        'type': 'hallucination',
        'sentenceIndexes': [1, 4],
      });
      expect(draft.toggle(1).toggle(4).toAnswer(), isNull);
    });

    test('is empty for a new exercise and rejects unknown sentences', () {
      final draft = AnswerDraft.empty(exercise);

      expect(draft, isA<HallucinationDraft>());
      draft as HallucinationDraft;
      expect(draft.selectedIndexes, isEmpty);
      expect(draft.toAnswer(), isNull, reason: 'check stays disabled');
      expect(
        () => draft.toggle(exercise.sentences.length),
        throwsArgumentError,
      );
    });
  });
}

const _capturedWrong = r'''
{"attemptId": "ed7f196a92794e9d97016cbf9f0f9583", "correct": false, "result": {"type": "hallucination", "errors": [{"index": 1, "errorType": "number", "correction": "高さは 3776 メートルです。", "tip": "数字は 1 けたちがうだけで大きなまちがい。地図帳で確かめよう。"}, {"index": 4, "errorType": "fake_source", "correction": "『世界山岳白書』という資料はなく、山頂をめざす登山者は 1 年に 20 万人ほどです。", "tip": "それらしい資料の名前が出てきたら、本当にあるか調べてみよう。"}], "found": [4], "missed": [1], "falseAlarms": [0]}, "progress": {"xp": 0, "xpGained": 0, "streakDays": 0}}
''';
