import '../../support/answer_selection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/live_check_lesson.dart';
import 'lesson_flow_test.dart' show openLesson, pumpApp, tapKey, textOf;

typedef F = LiveCheckLessonFixture;

final _input = find.byKey(const Key('live-check-input'));

/// The scrollable list of the current exercise (not the action panel).
Finder get _exerciseList => find
    .descendant(
      of: find.byKey(const Key('exercise-${LiveCheckLessonFixture.liveId}')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the exercise until [key] is built and visible.
Future<Finder> showInExercise(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(finder, 120, scrollable: _exerciseList);
  await tester.pumpAndSettle();
  return finder;
}

Future<void> tapInExercise(WidgetTester tester, String key) async {
  await tester.tap(await showInExercise(tester, key));
  await tester.pumpAndSettle();
}

/// The text of the [Text] widget with [key] in the exercise.
Future<String> exerciseText(WidgetTester tester, String key) async =>
    tester.widget<Text>(await showInExercise(tester, key)).data!;

/// Opens the lesson and answers its choice exercise.
Future<void> reachLiveCheck(WidgetTester tester) async {
  await openLesson(tester, F.lessonId);
  await tapKey(tester, 'choice-option-b');
  await tapKey(tester, 'lesson-check');
  await tapKey(tester, 'lesson-next');
  await showInExercise(tester, 'live-check-how');
}

Future<void> write(WidgetTester tester, String text) async {
  await showInExercise(tester, 'live-check-input');
  await tester.enterText(_input, text);
  await tester.pumpAndSettle();
}

String inputText(WidgetTester tester) =>
    tester.widget<TextField>(_input).controller!.text;

/// Asks with a suggestion, looks up the rewritten sentence, marks it and
/// clears the lesson. Shared with the responsive test.
Future<void> playLiveCheck(WidgetTester tester, FakeLearningApi api) async {
  await reachLiveCheck(tester);

  // The local check warns before anything is sent; editing is suggested.
  await write(tester, '富士山の高さは？ 連絡先は 090-1234-5678');
  await showInExercise(tester, 'prompt-personal-info-warning');
  await tapKey(tester, 'live-check-send');
  expect(
    find.byKey(const Key('live-check-personal-info-dialog')),
    findsOneWidget,
  );
  await tapKey(tester, 'live-check-edit-again');
  expect(api.liveCheckBodies, isEmpty);

  await tapInExercise(tester, 'live-check-suggestion-0');
  expect(inputText(tester), F.liveCheck.suggestions.first);
  expect(await exerciseText(tester, 'live-check-counter'), '18 / 200 文字');
  await tapKey(tester, 'live-check-send');

  expect(await exerciseText(tester, 'live-check-lookups-left'), contains('2'));
  expect(find.textContaining(F.correction), findsNothing, reason: 'secret');
  await showInExercise(tester, 'live-check-answer');
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('live-check-answer')))
        .controller!
        .text,
    contains(F.answer.sentences.first),
  );

  await lookupAnswerSentence(tester, 0);
  await showInExercise(tester, 'live-check-sources-0');
  expect(find.text('fuji-net.co.jp'), findsOneWidget);
  expect(find.textContaining(F.correction), findsNothing, reason: 'secret');
  expect(await exerciseText(tester, 'live-check-lookups-left'), contains('1'));

  await toggleAnswerSentence(tester, 'live-check', F.wrongIndex);
  expect(find.byType(InputChip), findsOneWidget);
  await tapKey(tester, 'live-check-submit');

  expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
  expect(find.byKey(const Key('live-check-feedback')), findsOneWidget);
  expect(find.textContaining(F.correction), findsWidgets);
  await tapKey(tester, 'live-check-feedback-sources');
  expect(find.textContaining(F.tip), findsWidgets);
  await tapKey(tester, 'lesson-next');

  expect(find.text('レッスンクリア！'), findsOneWidget);
}

void main() {
  testWidgets('asks the AI, investigates with a lookup and clears', (
    tester,
  ) async {
    final api = F.api();
    await pumpApp(tester, api: api, content: F.content());

    await playLiveCheck(tester, api);

    expect(api.liveCheckBodies.single['prompt'], F.liveCheck.suggestions.first);
    expect(api.lookupIndexes, [0]);
    expect(textOf(tester, 'result-xp-gained'), contains('+40 XP'));
    expect(api.completed, {F.lessonId});
  });

  testWidgets('an off-topic question is a teaching moment and keeps the text', (
    tester,
  ) async {
    final api = F.api();
    await pumpApp(tester, api: api, content: F.content());
    await reachLiveCheck(tester);
    const question = 'おすすめのゲームを教えて';

    await write(tester, question);
    await tapKey(tester, 'live-check-send');

    await showInExercise(tester, 'live-check-blocked');
    expect(find.text('テーマからはなれているみたい'), findsOneWidget);
    expect(inputText(tester), question);
    expect(api.liveCheckSessions, isEmpty);
  });

  testWidgets('with AI off the learner is told why and can skip', (
    tester,
  ) async {
    final api = F.api()..liveCheckAnswer = null;
    await pumpApp(tester, api: api, content: F.content());
    await reachLiveCheck(tester);

    await tapInExercise(tester, 'live-check-suggestion-1');
    await tapKey(tester, 'live-check-send');

    expect(
      find.byKey(const Key('live-check-failure-aiUnavailable')),
      findsOneWidget,
    );
    expect(inputText(tester), F.liveCheck.suggestions[1]);
    await tapKey(tester, 'live-check-skip');
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
  });

  testWidgets('after the daily limit only skipping is offered', (tester) async {
    final api = F.api()
      ..failNext(
        '/v1/live-checks',
        FakeLearningApi.errorResponse(429, 'rate_limited'),
      );
    await pumpApp(tester, api: api, content: F.content());
    await reachLiveCheck(tester);

    await tapInExercise(tester, 'live-check-suggestion-0');
    await tapKey(tester, 'live-check-send');

    expect(
      find.byKey(const Key('live-check-failure-dailyLimit')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('live-check-send')), findsNothing);
    expect(find.byKey(const Key('live-check-skip')), findsOneWidget);
  });

  testWidgets('a wrong answer shows what was missed and comes back', (
    tester,
  ) async {
    final api = F.api();
    await pumpApp(tester, api: api, content: F.content());
    await reachLiveCheck(tester);
    await tapInExercise(tester, 'live-check-suggestion-0');
    await tapKey(tester, 'live-check-send');

    await toggleAnswerSentence(tester, 'live-check', 1);
    await tapKey(tester, 'live-check-submit');

    expect(find.byKey(const Key('feedback-incorrect')), findsOneWidget);
    expect(find.text('見のがし'), findsWidgets);
    expect(find.text('正しい文だったよ'), findsWidgets);
    await tapKey(tester, 'lesson-next');
    expect(find.byKey(const Key('review-badge')), findsOneWidget);
    await showInExercise(tester, 'live-check-how');
  });
}
