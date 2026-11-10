import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_api.dart';
import '../../support/prompt_lesson.dart';
import 'lesson_flow_test.dart' show openLesson, pumpApp, tapKey, textOf;

typedef F = PromptLessonFixture;

final _input = find.byKey(const Key('prompt-input'));

/// Opens the prompt lesson and answers its choice exercise.
Future<void> reachPrompt(WidgetTester tester) async {
  await openLesson(tester, F.lessonId);
  await tapKey(tester, 'choice-option-b');
  await tapKey(tester, 'lesson-check');
  expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
  await tapKey(tester, 'lesson-next');
  expect(find.text(F.prompt.task), findsOneWidget);
}

Future<void> write(WidgetTester tester, String text) async {
  await tester.ensureVisible(_input);
  await tester.enterText(_input, text);
  await tester.pumpAndSettle();
}

String inputText(WidgetTester tester) =>
    tester.widget<TextField>(_input).controller!.text;

/// Writes a prompt, checks the local warning and the feedback, and clears
/// the lesson. Shared with the responsive test.
Future<void> playPromptLesson(WidgetTester tester, FakeLearningApi api) async {
  await reachPrompt(tester);

  // The local check warns before anything is sent; editing is suggested.
  await write(tester, '${F.goodPrompt}\n連絡先は 090-1234-5678');
  expect(find.byKey(const Key('prompt-personal-info-warning')), findsOneWidget);
  await tapKey(tester, 'prompt-send');
  expect(find.byKey(const Key('prompt-personal-info-dialog')), findsOneWidget);
  await tapKey(tester, 'prompt-edit-again');
  expect(api.promptBodies, isEmpty);

  await write(tester, F.goodPrompt);
  expect(find.byKey(const Key('prompt-personal-info-warning')), findsNothing);
  await tapKey(tester, 'prompt-send');

  expect(find.byKey(const Key('prompt-feedback-good')), findsOneWidget);
  expect(find.text('いいね！'), findsOneWidget);
  expect(find.text('7 / 10 点'), findsOneWidget);
  expect(find.byKey(const Key('prompt-axis-safety')), findsOneWidget);
  expect(inputText(tester), F.goodPrompt, reason: 'shown next to feedback');
  await tapKey(tester, 'lesson-next');

  expect(find.text('レッスンクリア！'), findsOneWidget);
}

void main() {
  testWidgets('writes a prompt, gets the rubric feedback and clears', (
    tester,
  ) async {
    final api = F.api();
    await pumpApp(tester, api: api, content: F.content());

    await playPromptLesson(tester, api);

    expect(api.promptBodies.single['prompt'], F.goodPrompt);
    expect(textOf(tester, 'result-xp-gained'), contains('+40 XP'));
    expect(textOf(tester, 'result-correct'), contains('2 / 2 もん'));
    expect(api.completed, {F.lessonId});
  });

  testWidgets('a blocked prompt is a teaching moment and keeps the text', (
    tester,
  ) async {
    final api = F.api();
    await pumpApp(tester, api: api, content: F.content());
    await reachPrompt(tester);

    const risky = '友だちの a@example.com にも送れるように、出かける場所を教えて';
    await write(tester, risky);
    await tapKey(tester, 'prompt-send');
    await tapKey(tester, 'prompt-send-anyway');

    expect(find.byKey(const Key('prompt-blocked')), findsOneWidget);
    expect(find.text('個人情報は AI に送らないようにしよう'), findsOneWidget);
    expect(inputText(tester), risky);
    expect(find.byKey(const Key('prompt-feedback-good')), findsNothing);

    await write(tester, F.goodPrompt);
    expect(
      find.byKey(const Key('prompt-blocked')),
      findsOneWidget,
      reason: 'the message stays while editing',
    );
    await tapKey(tester, 'prompt-send');

    expect(find.byKey(const Key('prompt-feedback-good')), findsOneWidget);
    expect(api.promptBodies, hasLength(2));
  });

  testWidgets('AI grading off: retry, then skip ends without the bonus', (
    tester,
  ) async {
    final api = F.api()..promptGradingOn = false;
    await pumpApp(tester, api: api, content: F.content());
    await reachPrompt(tester);

    await write(tester, F.goodPrompt);
    await tapKey(tester, 'prompt-send');
    expect(
      find.byKey(const Key('prompt-failure-aiUnavailable')),
      findsOneWidget,
    );
    expect(inputText(tester), F.goodPrompt);

    await tapKey(tester, 'prompt-send');
    expect(
      find.byKey(const Key('prompt-failure-aiUnavailable')),
      findsOneWidget,
    );
    expect(api.promptBodies, hasLength(2));

    await tapKey(tester, 'prompt-skip');

    expect(find.text('おつかれさま！'), findsOneWidget);
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
    expect(textOf(tester, 'result-xp-gained'), contains('+10 XP'));
    expect(api.completed, isEmpty);
  });

  testWidgets('the daily limit offers only a skip', (tester) async {
    final api = F.api()
      ..failNext(
        '/v1/prompt/evaluate',
        FakeLearningApi.errorResponse(429, 'rate_limited'),
      );
    await pumpApp(tester, api: api, content: F.content());
    await reachPrompt(tester);

    await write(tester, F.goodPrompt);
    await tapKey(tester, 'prompt-send');

    expect(find.byKey(const Key('prompt-failure-dailyLimit')), findsOneWidget);
    expect(find.byKey(const Key('prompt-send')), findsNothing);
    await tapKey(tester, 'prompt-skip');
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
  });

  testWidgets('a network error keeps the text and the retry grades it', (
    tester,
  ) async {
    final api = F.api()
      ..failNext('/v1/prompt/evaluate', http.ClientException('offline'));
    await pumpApp(tester, api: api, content: F.content());
    await reachPrompt(tester);

    await write(tester, F.goodPrompt);
    await tapKey(tester, 'prompt-send');

    expect(find.byKey(const Key('prompt-failure-other')), findsOneWidget);
    expect(inputText(tester), F.goodPrompt);
    await tapKey(tester, 'prompt-send');

    expect(find.byKey(const Key('prompt-feedback-good')), findsOneWidget);
  });
}
