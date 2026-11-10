import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/widgets/answer_feedback_panel.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_feedback_view.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_labels.dart';
import 'package:ailearn/models/answer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/hallucination.dart';
import 'exercise_widgets_test.dart' show pumpView;

final exercise = hallucinationFixture.exercise;

/// The fixture graded as if the learner tapped 0 and 4: 4 found, 1 missed,
/// 0 a false alarm.
HallucinationResult partlyWrong() => HallucinationResult(
  errors: [
    for (final e in hallucinationFixture.answerKey['errors']! as List)
      HallucinationError.fromJson(e),
  ]..sort((a, b) => a.index.compareTo(b.index)),
  found: const [4],
  missed: const [1],
  falseAlarms: const [0],
);

HallucinationReview review(HallucinationResult result) =>
    HallucinationReview.resolve(exercise, result);

Finder inSentence(int index, Finder matching) => find.descendant(
  of: find.byKey(Key('hallucination-sentence-$index')),
  matching: matching,
);

void main() {
  test('every error type has a learner label', () {
    expect(HallucinationErrorType.values.map(hallucinationErrorLabel), [
      '数字',
      '日付',
      '名前',
      'ないはずの出典',
      '原因と結果',
      '事実',
    ]);
  });

  group('HallucinationExerciseView', () {
    testWidgets('shows the topic, the error count and the sentences', (
      tester,
    ) async {
      final toggled = <int>[];
      await pumpView(
        tester,
        HallucinationExerciseView(
          exercise: exercise,
          selectedIndexes: const {},
          review: null,
          onToggle: toggled.add,
        ),
      );

      expect(find.text('AI の答え：富士山'), findsOneWidget);
      expect(find.text('まちがっている文をタップしよう'), findsOneWidget);
      expect(find.text('まちがいは 2 こ'), findsOneWidget);
      expect(find.text('えらんだ文：0 こ'), findsOneWidget);
      for (final sentence in exercise.sentences) {
        expect(find.text(sentence.text), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('hallucination-sentence-3')));
      expect(toggled, [3]);
    });

    testWidgets('selected sentences are marked with an icon and text', (
      tester,
    ) async {
      await pumpView(
        tester,
        HallucinationExerciseView(
          exercise: exercise,
          selectedIndexes: const {1, 3},
          review: null,
          onToggle: (_) {},
        ),
      );

      expect(find.text('えらんだ文：2 こ'), findsOneWidget);
      for (final index in [1, 3]) {
        expect(inSentence(index, find.text('まちがいとしてえらんだ')), findsOneWidget);
        expect(
          inSentence(index, find.byIcon(Icons.flag_rounded)),
          findsOneWidget,
        );
      }
      expect(inSentence(0, find.text('まちがいとしてえらんだ')), findsNothing);
      expect(
        inSentence(0, find.byIcon(Icons.outlined_flag_rounded)),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const Key('hallucination-sentence-1'))),
        isSemantics(isButton: true, isSelected: true),
      );
    });

    testWidgets('after checking, every sentence shows its verdict', (
      tester,
    ) async {
      await pumpView(
        tester,
        HallucinationExerciseView(
          exercise: exercise,
          selectedIndexes: const {0, 4},
          review: review(partlyWrong()),
          onToggle: null,
        ),
      );

      expect(inSentence(0, find.text('正しい文だったよ')), findsOneWidget);
      expect(inSentence(1, find.text('見のがし')), findsOneWidget);
      expect(inSentence(1, find.text('まちがいの種類：数字')), findsOneWidget);
      expect(inSentence(2, find.text('正しい文')), findsOneWidget);
      expect(inSentence(3, find.text('正しい文')), findsOneWidget);
      expect(inSentence(4, find.text('見つけた！')), findsOneWidget);
      expect(inSentence(4, find.text('まちがいの種類：ないはずの出典')), findsOneWidget);
      expect(find.text('まちがいとしてえらんだ'), findsNothing);
      await tester.tap(find.byKey(const Key('hallucination-sentence-2')));
    });
  });

  group('HallucinationFeedbackView', () {
    testWidgets('lists found and missed errors and false alarms', (
      tester,
    ) async {
      await pumpView(
        tester,
        HallucinationFeedbackView(review: review(partlyWrong())),
      );

      expect(find.text('まちがい 2 こ中 1 こ見つけたよ'), findsOneWidget);
      Finder inEntry(String key, Finder matching) => find.descendant(
        of: find.byKey(Key('hallucination-feedback-$key')),
        matching: matching,
      );
      expect(inEntry('error-1', find.text('2 文目')), findsOneWidget);
      expect(inEntry('error-1', find.text('見のがし')), findsOneWidget);
      expect(inEntry('error-1', find.text('まちがいの種類：数字')), findsOneWidget);
      expect(
        inEntry('error-1', find.text('正しくは：高さは 3776 メートルです。')),
        findsOneWidget,
      );
      expect(
        inEntry('error-1', find.textContaining('見ぬくコツ：数字は')),
        findsOneWidget,
      );
      expect(inEntry('error-4', find.text('見つけた！')), findsOneWidget);
      expect(inEntry('error-4', find.text('まちがいの種類：ないはずの出典')), findsOneWidget);
      expect(
        inEntry('error-4', find.textContaining('正しくは：『世界山岳白書』')),
        findsOneWidget,
      );
      expect(inEntry('false-alarm-0', find.text('正しい文だったよ')), findsOneWidget);
      expect(
        inEntry('false-alarm-0', find.text('富士山は日本でいちばん高い山です。')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('hallucination-feedback-error-1')))
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const Key('hallucination-feedback-error-4')),
              )
              .dy,
        ),
        reason: 'reading order',
      );
    });

    testWidgets('a perfect answer has no false alarms', (tester) async {
      await pumpView(
        tester,
        HallucinationFeedbackView(
          review: review(
            HallucinationResult(
              errors: partlyWrong().errors,
              found: const [1, 4],
              missed: const [],
              falseAlarms: const [],
            ),
          ),
        ),
      );

      expect(find.text('まちがい 2 こ中 2 こ見つけたよ'), findsOneWidget);
      expect(find.text('見つけた！'), findsNWidgets(2));
      expect(find.text('見のがし'), findsNothing);
      expect(find.text('正しい文だったよ'), findsNothing);
    });
  });

  group('AnswerFeedbackPanel with a hallucination result', () {
    Checked checked({required bool correct, required HallucinationResult r}) =>
        Checked(
          SubmitAnswerResponse(
            attemptId: 'a1',
            correct: correct,
            result: r,
            progress: const ProgressSnapshot(xp: 0, xpGained: 0, streakDays: 0),
          ),
          CorrectHallucination(review(r)),
        );

    testWidgets('a wrong answer shows おしい！, the details and the review note', (
      tester,
    ) async {
      var next = 0;
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: checked(correct: false, r: partlyWrong()),
          step: LessonStep.first(exercise),
          onNext: () => next++,
        ),
      );

      expect(find.byKey(const Key('feedback-incorrect')), findsOneWidget);
      expect(find.text('おしい！'), findsOneWidget);
      expect(find.byKey(const Key('hallucination-feedback')), findsOneWidget);
      expect(find.text('正しい答え'), findsNothing);
      expect(find.byKey(const Key('feedback-explanation')), findsNothing);
      expect(find.text('この問題は、レッスンの最後にもう一度出るよ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lesson-next')));
      expect(next, 1);
    });

    testWidgets('a correct answer shows 正解！ and still the tips', (
      tester,
    ) async {
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: checked(
            correct: true,
            r: HallucinationResult(
              errors: partlyWrong().errors,
              found: const [1, 4],
              missed: const [],
              falseAlarms: const [],
            ),
          ),
          step: LessonStep.first(exercise),
          onNext: () {},
        ),
      );

      expect(find.text('正解！'), findsOneWidget);
      expect(find.textContaining('見ぬくコツ：'), findsNWidgets(2));
      expect(find.text('この問題は、レッスンの最後にもう一度出るよ'), findsNothing);
    });
  });
}
