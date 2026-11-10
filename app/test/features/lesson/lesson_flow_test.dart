import 'package:ailearn/data/repositories.dart';
import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_api.dart';
import '../../support/fakes.dart';
import '../../support/unit1.dart';

const learner = AppUser(uid: 'google-user', isAnonymous: false);

FakeLearningApi unit1Api({Map<String, List<String>>? lessonExercises}) =>
    FakeLearningApi(
      answerKeys: unit1.answerKeys,
      lessonExercises:
          lessonExercises ??
          {for (final l in unit1.lessons) l.id: l.exerciseIds},
    );

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeLearningApi api,
  FakeContentRepository? content,
}) async {
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
  );
  // A phone-sized portrait screen.
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    buildTestApp(
      auth: FakeAuthRepository(initialUser: learner),
      profiles: FakeProfileRepository({'google-user': sampleProfile}),
      content:
          content ??
          FakeContentRepository(
            units: [unit('u1', 1)],
            lessons: unit1.lessons,
            exercises: unit1.exercises,
          ),
      api: api,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openLesson(WidgetTester tester, String lessonId) async {
  await tapKey(tester, 'lesson-$lessonId-unlocked');
  await tapKey(tester, 'path-start-lesson');
  expect(find.byKey(const Key('lesson-intro')), findsOneWidget);
  await tapKey(tester, 'lesson-start');
}

Future<void> checkAndExpect(WidgetTester tester, String feedbackKey) async {
  await tapKey(tester, 'lesson-check');
  expect(find.byKey(Key(feedbackKey)), findsOneWidget);
}

/// Answers u1-l1-q2 .. q6 correctly through the UI.
Future<void> playRestOfLesson1(WidgetTester tester) async {
  await tapKey(tester, 'blank-next-option-b');
  await checkAndExpect(tester, 'feedback-correct');
  await tapKey(tester, 'lesson-next');

  await tapKey(tester, 'choice-option-c');
  await checkAndExpect(tester, 'feedback-correct');
  await tapKey(tester, 'lesson-next');

  for (final id in ['input', 'predict', 'append', 'repeat']) {
    await tapKey(tester, 'order-item-$id');
  }
  await checkAndExpect(tester, 'feedback-correct');
  await tapKey(tester, 'lesson-next');

  await tapKey(tester, 'choice-option-b');
  await checkAndExpect(tester, 'feedback-correct');
  await tapKey(tester, 'lesson-next');

  await tapKey(tester, 'blank-data-option-a');
  await tapKey(tester, 'blank-pattern-option-b');
  await checkAndExpect(tester, 'feedback-correct');
  await tapKey(tester, 'lesson-next');
}

String textOf(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .join(' ');
  return texts;
}

void main() {
  testWidgets('plays Unit 1 lesson 1 with a review and reaches the result', (
    tester,
  ) async {
    final api = unit1Api();
    await pumpApp(tester, api: api);

    await tapKey(tester, 'lesson-u1-l1-unlocked');
    await tapKey(tester, 'path-start-lesson');
    expect(find.text('AI はどうやって文章をつくる？'), findsOneWidget);
    expect(find.textContaining('のぞいてみよう。\nじつは'), findsOneWidget);
    expect(find.text('ぜんぶで 6 もん'), findsOneWidget);
    await tapKey(tester, 'lesson-start');

    // q1: the check button waits for an answer.
    expect(find.text('0 / 6'), findsOneWidget);
    final check = tester.widget<FilledButton>(
      find.byKey(const Key('lesson-check')),
    );
    expect(check.onPressed, isNull);
    await tapKey(tester, 'choice-option-a');
    await checkAndExpect(tester, 'feedback-incorrect');
    expect(find.text('おしい！'), findsOneWidget);
    expect(find.text('それまでの文の続きとして、次に来そうなことばを予測する'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('feedback-explanation'))).data,
      contains('\n'),
    );
    expect(find.text('1 / 7'), findsOneWidget, reason: 'review queued');
    await tapKey(tester, 'lesson-next');

    await playRestOfLesson1(tester);

    // The review of q1 comes last.
    expect(find.byKey(const Key('review-badge')), findsOneWidget);
    expect(find.text('6 / 7'), findsOneWidget);
    await tapKey(tester, 'choice-option-b');
    await checkAndExpect(tester, 'feedback-correct');
    await tapKey(tester, 'lesson-next');

    expect(find.text('レッスンクリア！'), findsOneWidget);
    expect(textOf(tester, 'result-xp-gained'), contains('+80 XP'));
    expect(textOf(tester, 'result-xp-total'), contains('80 XP'));
    expect(textOf(tester, 'result-streak'), contains('1 日'));
    expect(textOf(tester, 'result-correct'), contains('5 / 6 もん'));
    expect(api.answerBodies, hasLength(7));
    expect(api.completed, {'u1-l1'});

    await tapKey(tester, 'lesson-back-to-path');
    expect(find.text('学習パス'), findsOneWidget);
  });

  testWidgets('skipped exercises end without the bonus after a 409', (
    tester,
  ) async {
    final lessonJson = unit1.lessonJson('u1-l1');
    (lessonJson['exerciseIds']! as List).add('u1-l1-q7');
    final lesson = Lesson.fromJson(lessonJson);
    final api = unit1Api(lessonExercises: {'u1-l1': lesson.exerciseIds})
      ..promptGradingOn = false;
    await pumpApp(
      tester,
      api: api,
      content: FakeContentRepository(
        units: [unit('u1', 1)],
        lessons: [lesson],
        exercises: [
          ...unit1.exercises,
          const PromptExercise(
            id: 'u1-l1-q7',
            lessonId: 'u1-l1',
            question: 'プロンプトを書こう',
            task: '自由研究のテーマを AI に相談しよう',
            maxLength: 400,
          ),
        ],
      ),
    );
    await openLesson(tester, 'u1-l1');

    await tapKey(tester, 'choice-option-b');
    await checkAndExpect(tester, 'feedback-correct');
    await tapKey(tester, 'lesson-next');
    await playRestOfLesson1(tester);

    // AI grading is off, so the prompt exercise is skipped.
    expect(find.byKey(const Key('lesson-check')), findsNothing);
    await tester.enterText(find.byKey(const Key('prompt-input')), '自由研究のテーマ');
    await tapKey(tester, 'prompt-send');
    expect(
      find.byKey(const Key('prompt-failure-aiUnavailable')),
      findsOneWidget,
    );
    await tapKey(tester, 'prompt-skip');

    expect(find.text('おつかれさま！'), findsOneWidget);
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
    expect(textOf(tester, 'result-xp-gained'), contains('+60 XP'));
    expect(textOf(tester, 'result-xp-total'), contains('60 XP'));
    expect(
      api.answerBodies.map((b) => b['exerciseId']),
      isNot(contains('u1-l1-q7')),
    );
    expect(api.completed, isEmpty);
  });

  testWidgets('a failed send keeps the selection and can be retried', (
    tester,
  ) async {
    final api = unit1Api()
      ..failNext('/v1/answers', http.ClientException('offline'));
    await pumpApp(tester, api: api);
    await openLesson(tester, 'u1-l1');

    await tapKey(tester, 'choice-option-b');
    await tapKey(tester, 'lesson-check');

    expect(find.byKey(const Key('lesson-submit-error')), findsOneWidget);
    expect(find.text('もう一度送る'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('choice-option-b')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
      reason: 'the selection is kept',
    );

    await tapKey(tester, 'lesson-check');

    expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
    expect(api.answerBodies, hasLength(2));
  });

  testWidgets('a failed completion offers a retry', (tester) async {
    final api = unit1Api()
      ..failNext(
        '/v1/lessons/u1-l1/complete',
        FakeLearningApi.errorResponse(503, 'upstream_unavailable'),
      );
    await pumpApp(tester, api: api);
    await openLesson(tester, 'u1-l1');
    await tapKey(tester, 'choice-option-b');
    await checkAndExpect(tester, 'feedback-correct');
    await tapKey(tester, 'lesson-next');
    await playRestOfLesson1(tester);

    expect(find.byKey(const Key('lesson-complete-failed')), findsOneWidget);
    await tapKey(tester, 'lesson-complete-retry');

    expect(find.text('レッスンクリア！'), findsOneWidget);
  });

  testWidgets('closing the lesson goes back to the path', (tester) async {
    await pumpApp(tester, api: unit1Api());

    await tapKey(tester, 'lesson-u1-l1-unlocked');
    await tapKey(tester, 'path-start-lesson');
    await tapKey(tester, 'lesson-close');

    expect(find.text('学習パス'), findsOneWidget);
  });

  testWidgets('an unknown lesson shows a way back', (tester) async {
    await pumpApp(tester, api: unit1Api());

    GoRouter.of(tester.element(find.text('学習パス'))).go('/lessons/u9-l9');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-not-found')), findsOneWidget);
    await tapKey(tester, 'lesson-close');
    expect(find.text('学習パス'), findsOneWidget);
  });
}
