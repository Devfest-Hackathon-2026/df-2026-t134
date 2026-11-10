import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/widgets/prompt_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/prompt_feedback_view.dart';
import 'package:ailearn/features/lesson/widgets/prompt_send_bar.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/prompt_lesson.dart';
import 'exercise_widgets_test.dart' show pumpView;

typedef F = PromptLessonFixture;

/// [PromptExerciseView] whose edits update its draft, like the controller.
class _EditableHost extends StatefulWidget {
  const _EditableHost({required this.initial});

  final PromptDraft initial;

  @override
  State<_EditableHost> createState() => _EditableHostState();
}

class _EditableHostState extends State<_EditableHost> {
  late PromptDraft draft = widget.initial;

  @override
  Widget build(BuildContext context) => PromptExerciseView(
    draft: draft,
    onChanged: (text) => setState(() => draft = draft.edit(text)),
  );
}

String counterText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('prompt-counter'))).data!;

PromptEvaluated evaluation({required int total, int xpGained = 10}) =>
    PromptEvaluated(
      attemptId: 'a1',
      total: total,
      scores: RubricScores(
        purpose: 2,
        context: total >= 6 ? 2 : 0,
        constraints: 1,
        format: total >= 6 ? 1 : 0,
        safety: total >= 6 ? 1 : 0,
      ),
      goodPoint: '目的がはっきりしているね。',
      improvements: const ['人数を書こう', '予算を書こう'],
      hint: '答えの形を決めよう',
      progress: ProgressSnapshot(xp: 10, xpGained: xpGained, streakDays: 0),
    );

void main() {
  group('PromptExerciseView', () {
    testWidgets('shows the task, the five elements and a live counter', (
      tester,
    ) async {
      await pumpView(tester, _EditableHost(initial: PromptDraft(F.prompt)));

      expect(find.text(F.prompt.task), findsOneWidget);
      for (final name in ['役割', '目的', '前提', '条件', '出力形式']) {
        expect(
          find.descendant(
            of: find.byKey(const Key('prompt-elements-hint')),
            matching: find.textContaining(name, findRichText: true),
          ),
          findsWidgets,
          reason: name,
        );
      }
      expect(counterText(tester), '0 / 400 文字');

      await tester.enterText(find.byKey(const Key('prompt-input')), 'こんにちは');
      await tester.pump();

      expect(counterText(tester), '5 / 400 文字');
    });

    testWidgets('stops at maxLength', (tester) async {
      await pumpView(tester, _EditableHost(initial: PromptDraft(F.prompt)));

      await tester.enterText(
        find.byKey(const Key('prompt-input')),
        'あ' * (F.prompt.maxLength + 20),
      );
      await tester.pump();

      expect(counterText(tester), '400 / 400 文字');
      expect(find.byKey(const Key('prompt-too-long')), findsNothing);
    });

    testWidgets('warns about personal information while typing', (
      tester,
    ) async {
      await pumpView(tester, _EditableHost(initial: PromptDraft(F.prompt)));
      final input = find.byKey(const Key('prompt-input'));

      await tester.enterText(input, '連絡は 090-1234-5678 か a@example.com へ');
      await tester.pump();

      final warning = find.byKey(const Key('prompt-personal-info-warning'));
      expect(warning, findsOneWidget);
      expect(
        find.descendant(
          of: warning,
          matching: find.textContaining('メールアドレス・電話番号のようなもの'),
        ),
        findsOneWidget,
      );

      await tester.enterText(input, '連絡はしないで');
      await tester.pump();
      expect(warning, findsNothing);
    });

    testWidgets('shows the blocked message and keeps the text', (tester) async {
      final draft = PromptDraft(F.prompt)
          .edit('090-1234-5678')
          .block(
            PromptBlocked(
              reasons: const [PromptBlockReason.personalInfo],
              message: '電話番号のような個人情報が入っているみたい。',
            ),
          );
      await pumpView(tester, _EditableHost(initial: draft));

      final notice = find.byKey(const Key('prompt-blocked'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(
          of: notice,
          matching: find.text('個人情報は AI に送らないようにしよう'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notice, matching: find.textContaining('電話番号のような')),
        findsOneWidget,
      );
      expect(find.text('090-1234-5678'), findsOneWidget);
    });

    testWidgets('is read-only without onChanged', (tester) async {
      await pumpView(
        tester,
        PromptExerciseView(
          draft: PromptDraft(F.prompt).edit('090-1234-5678'),
          onChanged: null,
        ),
      );

      final field = tester.widget<TextField>(
        find.byKey(const Key('prompt-input')),
      );
      expect(field.readOnly, isTrue);
      expect(
        find.byKey(const Key('prompt-personal-info-warning')),
        findsNothing,
      );
    });
  });

  group('PromptSendBar', () {
    (List<String>, Widget) bar(PromptDraft draft, StepStatus status) {
      final calls = <String>[];
      return (
        calls,
        PromptSendBar(
          draft: draft,
          status: status,
          onSend: () => calls.add('send'),
          onSkip: () => calls.add('skip'),
        ),
      );
    }

    FilledButton sendButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('prompt-send')));

    testWidgets('waits for text that fits', (tester) async {
      for (final text in ['', '  \n', 'あ' * 401]) {
        final (_, widget) = bar(
          PromptDraft(F.prompt).edit(text),
          const Answering(),
        );
        await pumpView(tester, widget);
        expect(sendButton(tester).onPressed, isNull, reason: text);
        expect(find.text('AI に採点してもらう'), findsOneWidget);
        expect(find.byKey(const Key('prompt-skip')), findsNothing);
      }
      expect(find.text('400 文字以内にしたら送れるよ'), findsOneWidget);
    });

    testWidgets('sends right away without personal information', (
      tester,
    ) async {
      final (calls, widget) = bar(
        PromptDraft(F.prompt).edit(F.goodPrompt),
        const Answering(),
      );
      await pumpView(tester, widget);

      await tester.tap(find.byKey(const Key('prompt-send')));
      await tester.pumpAndSettle();

      expect(calls, ['send']);
      expect(
        find.byKey(const Key('prompt-personal-info-dialog')),
        findsNothing,
      );
    });

    testWidgets('asks before sending personal information', (tester) async {
      final (calls, widget) = bar(
        PromptDraft(F.prompt).edit('電話は 090-1234-5678'),
        const Answering(),
      );
      await pumpView(tester, widget);

      await tester.tap(find.byKey(const Key('prompt-send')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('prompt-personal-info-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('電話番号のようなもの'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prompt-edit-again')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'editing is the recommended answer');

      await tester.tap(find.byKey(const Key('prompt-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prompt-send-anyway')));
      await tester.pumpAndSettle();
      expect(calls, ['send'], reason: 'the server stays the authority');
    });

    testWidgets('shows a spinner while sending', (tester) async {
      final (_, widget) = bar(
        PromptDraft(F.prompt).edit(F.goodPrompt),
        const Submitting(),
      );
      await pumpView(tester, widget);

      expect(sendButton(tester).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AI grading off offers a retry and a skip', (tester) async {
      final (calls, widget) = bar(
        PromptDraft(F.prompt).edit(F.goodPrompt),
        const SubmitFailed(
          ApiException(
            statusCode: 503,
            path: '/v1/prompt/evaluate',
            code: ApiErrorCode.upstreamUnavailable,
          ),
        ),
      );
      await pumpView(tester, widget);

      expect(
        find.byKey(const Key('prompt-failure-aiUnavailable')),
        findsOneWidget,
      );
      expect(find.text('いまは AI の採点がお休み中だよ'), findsOneWidget);
      expect(find.text('もう一度送る'), findsOneWidget);
      await tester.tap(find.byKey(const Key('prompt-skip')));
      await tester.tap(find.byKey(const Key('prompt-send')));
      await tester.pumpAndSettle();
      expect(calls, ['skip', 'send']);
    });

    testWidgets('the daily limit only offers a skip', (tester) async {
      final (calls, widget) = bar(
        PromptDraft(F.prompt).edit(F.goodPrompt),
        const SubmitFailed(
          ApiException(
            statusCode: 429,
            path: '/v1/prompt/evaluate',
            code: ApiErrorCode.rateLimited,
          ),
        ),
      );
      await pumpView(tester, widget);

      expect(
        find.byKey(const Key('prompt-failure-dailyLimit')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('prompt-send')), findsNothing);
      await tester.tap(find.byKey(const Key('prompt-skip')));
      expect(calls, ['skip']);
    });

    testWidgets('a network error offers a retry', (tester) async {
      final (calls, widget) = bar(
        PromptDraft(F.prompt).edit(F.goodPrompt),
        SubmitFailed(http.ClientException('offline')),
      );
      await pumpView(tester, widget);

      expect(find.byKey(const Key('prompt-failure-other')), findsOneWidget);
      await tester.tap(find.byKey(const Key('prompt-send')));
      await tester.pumpAndSettle();
      expect(calls, ['send']);
    });

    test('failures are told apart by error code only', () {
      ApiException withCode(ApiErrorCode? code, int status) =>
          ApiException(statusCode: status, path: '/v1/x', code: code);

      expect(
        PromptFailure.of(withCode(ApiErrorCode.upstreamUnavailable, 503)),
        PromptFailure.aiUnavailable,
      );
      expect(
        PromptFailure.of(withCode(ApiErrorCode.rateLimited, 429)),
        PromptFailure.dailyLimit,
      );
      expect(PromptFailure.of(withCode(null, 503)), PromptFailure.other);
      expect(
        PromptFailure.of(withCode(ApiErrorCode.internal, 500)),
        PromptFailure.other,
      );
      expect(
        PromptFailure.of(const FormatException('bad')),
        PromptFailure.other,
      );
    });
  });

  group('PromptFeedbackView', () {
    testWidgets('a passing total says いいね！ with every part', (tester) async {
      final handle = tester.ensureSemantics();
      var next = 0;
      await pumpView(
        tester,
        PromptFeedbackView(
          evaluation: evaluation(total: 7),
          onNext: () => next++,
        ),
      );

      expect(find.byKey(const Key('prompt-feedback-good')), findsOneWidget);
      expect(find.text('いいね！'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_alt_rounded), findsOneWidget);
      expect(find.text('7 / 10 点'), findsOneWidget);
      expect(find.text('+10 XP'), findsOneWidget);
      for (final (axis, label) in [
        ('purpose', '目的'),
        ('context', '前提・文脈'),
        ('constraints', '条件・制約'),
        ('format', '出力形式'),
        ('safety', '安全'),
      ]) {
        expect(find.byKey(Key('prompt-axis-$axis')), findsOneWidget);
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.bySemanticsLabel('目的 2 点中 2 点'),
        findsOneWidget,
        reason: 'the meter is read as text, not only drawn',
      );
      expect(find.bySemanticsLabel('条件・制約 2 点中 1 点'), findsOneWidget);
      expect(find.text('目的がはっきりしているね。'), findsOneWidget);
      expect(find.text('・人数を書こう'), findsOneWidget);
      expect(find.text('・予算を書こう'), findsOneWidget);
      expect(find.text('答えの形を決めよう'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lesson-next')));
      expect(next, 1);
      handle.dispose();
    });

    testWidgets('a low total says もう少し！ without XP', (tester) async {
      await pumpView(
        tester,
        PromptFeedbackView(
          evaluation: evaluation(total: 3, xpGained: 0),
          onNext: () {},
        ),
      );

      expect(find.byKey(const Key('prompt-feedback-more')), findsOneWidget);
      expect(find.text('もう少し！'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(find.text('3 / 10 点'), findsOneWidget);
      expect(find.byKey(const Key('prompt-xp')), findsNothing);
    });
  });
}
