import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/widgets/answer_feedback_panel.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_feedback_view.dart';
import 'package:ailearn/features/lesson/widgets/hallucination_labels.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/answer_mark.dart';

import '../../support/answer_selection.dart';

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
    testWidgets(
      'the whole answer is continuous and selecting a fragment marks its claim',
      (tester) async {
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
        final field = tester.widget<TextField>(
          find.byKey(const Key('hallucination-answer')),
        );
        expect(field.controller!.text, answerPassage(exercise.sentences));
        expect(field.readOnly, isTrue);
        expect(
          find.byKey(const Key('hallucination-error-count')),
          findsNothing,
        );
        expect(find.byKey(const Key('hallucination-sentence-0')), findsNothing);
        final bounds = sentenceMark(exercise.sentences, 1);
        await selectAnswerRange(
          tester,
          'hallucination',
          AnswerMark(bounds.start + 2, bounds.start + 5),
        );
        await tapAnswerControl(tester, 'hallucination-mark-selected');
        expect(toggled, [1]);
      },
    );
    testWidgets(
      'no error is an explicit answer and selected fragments can be removed',
      (tester) async {
        var confirmed = false;
        final removed = <AnswerMark>[];
        final mark = sentenceMark(exercise.sentences, 1);
        await pumpView(
          tester,
          HallucinationExerciseView(
            exercise: exercise,
            selectedIndexes: const {1},
            marks: [mark],
            review: null,
            onToggle: (_) {},
            onRemove: removed.add,
            onNoErrors: () => confirmed = true,
          ),
        );
        expect(find.byType(InputChip), findsOneWidget);
        await tapAnswerControl(tester, 'hallucination-no-errors');
        expect(confirmed, isTrue);
        final remove = find.byTooltip('この指定を取り消す');
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        expect(removed, [mark]);
      },
    );
    testWidgets('checked answers stay continuous and cannot be changed', (
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
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('hallucination-answer')))
            .controller!
            .text,
        answerPassage(exercise.sentences),
      );
      expect(
        find.byKey(const Key('hallucination-mark-selected')),
        findsNothing,
      );
      expect(find.byKey(const Key('hallucination-no-errors')), findsNothing);
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

      expect(find.text('誤り 2 か所のうち 1 か所を確認できたよ'), findsOneWidget);
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

      expect(find.text('誤り 2 か所のうち 2 か所を確認できたよ'), findsOneWidget);
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
