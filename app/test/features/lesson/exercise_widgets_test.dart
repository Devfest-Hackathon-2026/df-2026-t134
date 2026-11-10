import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/shuffle.dart';
import 'package:ailearn/features/lesson/widgets/answer_feedback_panel.dart';
import 'package:ailearn/features/lesson/widgets/choice_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/fill_blank_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/mascot_bubble.dart';
import 'package:ailearn/features/lesson/widgets/order_exercise_view.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/unit1.dart';

Future<void> pumpView(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('ChoiceExerciseView', () {
    final exercise = unit1.exercise<ChoiceExercise>('u1-l1-q1');

    testWidgets('tapping an option reports its id', (tester) async {
      final selected = <String>[];
      await pumpView(
        tester,
        ChoiceExerciseView(
          exercise: exercise,
          selectedOptionId: null,
          result: null,
          onSelect: selected.add,
        ),
      );

      for (final option in exercise.options) {
        expect(find.text(option.text), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('choice-option-c')));

      expect(selected, ['c']);
    });

    testWidgets('after checking, marks right and wrong with text', (
      tester,
    ) async {
      final selected = <String>[];
      await pumpView(
        tester,
        ChoiceExerciseView(
          exercise: exercise,
          selectedOptionId: 'a',
          result: const ChoiceResult(correctOptionId: 'b', explanation: ''),
          onSelect: null,
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('choice-option-b')),
          matching: find.text('せいかい'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('choice-option-a')),
          matching: find.text('ちがうよ'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('choice-option-c')));
      expect(selected, isEmpty);
    });
  });

  group('OrderExerciseView', () {
    final exercise = unit1.exercise<OrderExercise>('u1-l1-q4');

    Widget view({
      List<String> picked = const [],
      OrderResult? result,
      ValueChanged<String>? onAdd,
      ValueChanged<String>? onRemove,
      VoidCallback? onUndo,
    }) => OrderExerciseView(
      exercise: exercise,
      pickedIds: picked,
      result: result,
      onAdd: onAdd,
      onRemove: onRemove,
      onUndo: onUndo,
    );

    testWidgets('shows the items shuffled and adds the tapped one', (
      tester,
    ) async {
      final added = <String>[];
      await pumpView(tester, view(onAdd: added.add, onUndo: () {}));

      final shown = [
        for (final item in shuffledItems(exercise))
          tester.getTopLeft(find.byKey(Key('order-item-${item.id}'))).dy,
      ];
      expect(shown, orderedEquals([...shown]..sort()));
      expect(find.text('下のカードを、1 番目から順番にタップしてね'), findsOneWidget);
      final undo = tester.widget<TextButton>(
        find.byKey(const Key('order-undo')),
      );
      expect(undo.onPressed, isNull, reason: 'nothing to undo yet');

      await tester.tap(find.byKey(const Key('order-item-input')));
      expect(added, ['input']);
    });

    testWidgets('placed items are numbered, removable and undoable', (
      tester,
    ) async {
      final removed = <String>[];
      var undone = 0;
      await pumpView(
        tester,
        view(
          picked: ['input', 'predict'],
          onAdd: (_) {},
          onRemove: removed.add,
          onUndo: () => undone++,
        ),
      );

      expect(find.byKey(const Key('order-picked-input')), findsOneWidget);
      expect(find.byKey(const Key('order-item-input')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('order-picked-predict')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('order-picked-input')));
      await tester.tap(find.byKey(const Key('order-undo')));
      expect(removed, ['input']);
      expect(undone, 1);
    });

    testWidgets('after checking, each position is marked', (tester) async {
      await pumpView(
        tester,
        view(
          picked: ['input', 'append', 'predict', 'repeat'],
          result: const OrderResult(
            correctOrder: ['input', 'predict', 'append', 'repeat'],
            explanation: '',
          ),
        ),
      );

      expect(find.text('せいかい'), findsNWidgets(2));
      expect(find.text('ちがうよ'), findsNWidgets(2));
    });
  });

  group('FillBlankExerciseView', () {
    final exercise = unit1.exercise<FillBlankExercise>('u1-l1-q6');

    testWidgets('renders the template with empty numbered slots', (
      tester,
    ) async {
      final chosen = <(String, String)>[];
      await pumpView(
        tester,
        FillBlankExerciseView(
          exercise: exercise,
          selected: const {},
          result: null,
          onChoose: (blank, option) => chosen.add((blank, option)),
        ),
      );

      expect(
        find.textContaining('生成 AI は、大量の', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('① ？？？'), findsOneWidget);
      expect(find.text('② ？？？'), findsOneWidget);
      expect(find.text('空らん① に入ることば'), findsOneWidget);

      await tester.tap(find.byKey(const Key('blank-pattern-option-b')));
      expect(chosen, [('pattern', 'b')]);
    });

    testWidgets('shows chosen words in the slots and marks them', (
      tester,
    ) async {
      await pumpView(
        tester,
        FillBlankExerciseView(
          exercise: exercise,
          selected: const {'data': 'a', 'pattern': 'a'},
          result: const FillBlankResult(
            correctOptions: {'data': 'a', 'pattern': 'b'},
            explanation: '',
          ),
          onChoose: null,
        ),
      );

      expect(find.text('① 文章データ'), findsOneWidget);
      expect(find.text('② 正しさ'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    });
  });

  testWidgets('MascotBubble shows the speech with its line breaks', (
    tester,
  ) async {
    await pumpView(
      tester,
      const MascotBubble(speech: Speech(text: 'こんにちは！\nはじめよう')),
    );

    expect(find.text('こんにちは！\nはじめよう'), findsOneWidget);
  });

  group('AnswerFeedbackPanel', () {
    final exercise = unit1.exercise<ChoiceExercise>('u1-l1-q1');

    Checked checked({required bool correct}) => Checked(
      SubmitAnswerResponse(
        attemptId: 'a1',
        correct: correct,
        result: const ChoiceResult(
          correctOptionId: 'b',
          explanation: '1 行目\n2 行目',
        ),
        progress: const ProgressSnapshot(xp: 10, xpGained: 10, streakDays: 0),
      ),
      const CorrectText('次に来そうなことばを予測する'),
    );

    testWidgets('a correct answer says 正解！ with the explanation', (
      tester,
    ) async {
      var next = 0;
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: checked(correct: true),
          step: LessonStep.first(exercise),
          onNext: () => next++,
        ),
      );

      expect(find.text('正解！'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('正しい答え'), findsNothing);
      expect(find.text('1 行目\n2 行目'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lesson-next')));
      expect(next, 1);
    });

    testWidgets('a wrong answer shows the right one and the review note', (
      tester,
    ) async {
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: checked(correct: false),
          step: LessonStep.first(exercise),
          onNext: () {},
        ),
      );

      expect(find.text('おしい！'), findsOneWidget);
      expect(find.text('次に来そうなことばを予測する'), findsOneWidget);
      expect(find.text('この問題は、レッスンの最後にもう一度出るよ'), findsOneWidget);
    });

    testWidgets('a wrong review answer is not announced again', (tester) async {
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: checked(correct: false),
          step: LessonStep.review(exercise),
          onNext: () {},
        ),
      );

      expect(find.text('この問題は、レッスンの最後にもう一度出るよ'), findsNothing);
    });

    testWidgets('a correct sequence is numbered', (tester) async {
      await pumpView(
        tester,
        AnswerFeedbackPanel(
          checked: Checked(
            SubmitAnswerResponse(
              attemptId: 'a1',
              correct: false,
              result: const OrderResult(
                correctOrder: ['a', 'b'],
                explanation: '',
              ),
              progress: const ProgressSnapshot(
                xp: 0,
                xpGained: 0,
                streakDays: 0,
              ),
            ),
            CorrectSequence(['はじめ', 'つぎ']),
          ),
          step: LessonStep.first(exercise),
          onNext: () {},
        ),
      );

      expect(find.text('1. はじめ'), findsOneWidget);
      expect(find.text('2. つぎ'), findsOneWidget);
      expect(find.byKey(const Key('feedback-explanation')), findsNothing);
    });
  });
}
