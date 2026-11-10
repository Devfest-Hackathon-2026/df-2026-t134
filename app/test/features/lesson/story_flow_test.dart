import 'package:ailearn/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/story.dart';
import 'lesson_flow_test.dart' show openLesson, pumpApp, tapKey, textOf;

String bestOf(StoryExercise exercise) =>
    storyFixture.answerKeys[exercise.id]!['bestOptionId']! as String;

String otherOf(StoryExercise exercise) =>
    exercise.options.firstWhere((o) => o.id != bestOf(exercise)).id;

int outcomeLength(StoryExercise exercise, String optionId) {
  final outcomes = storyFixture.answerKeys[exercise.id]!['outcomes']! as List;
  return ((outcomes.singleWhere((o) => (o as Map)['optionId'] == optionId)
              as Map)['scenes']!
          as List)
      .length;
}

/// Plays [exercise] through the UI: every scene, the choice, every outcome
/// scene, then the feedback ([feedbackKey]).
Future<void> playStory(
  WidgetTester tester,
  StoryExercise exercise, {
  required String optionId,
  required String feedbackKey,
  bool skip = false,
}) async {
  if (skip) {
    await tapKey(tester, 'story-skip');
  } else {
    for (var i = 0; i < exercise.scenes.length; i++) {
      expect(
        find.text('場面 ${i + 1} / ${exercise.scenes.length}'),
        findsOneWidget,
      );
      expect(find.text(exercise.scenes[i].text), findsOneWidget);
      await tapKey(tester, 'story-next');
    }
  }
  expect(find.text(exercise.question), findsOneWidget);
  await tapKey(tester, 'choice-option-$optionId');
  await tapKey(tester, 'lesson-check');
  final scenes = outcomeLength(exercise, optionId);
  for (var i = 0; i < scenes; i++) {
    expect(find.text('そのあと ${i + 1} / $scenes'), findsOneWidget);
    expect(find.byKey(Key(feedbackKey)), findsNothing);
    await tapKey(tester, 'story-next');
  }
  expect(find.byKey(Key(feedbackKey)), findsOneWidget);
}

void main() {
  testWidgets('plays the story lesson with a review and reaches the result', (
    tester,
  ) async {
    final setup = storyFixture.setup();
    final [first, second, third] = storyFixture.exercises;
    await pumpApp(tester, api: setup.api, content: setup.content);
    await openLesson(tester, StoryFixture.lessonId);
    expect(find.text('0 / 3'), findsOneWidget);

    // The scenes come one at a time; the question only after them.
    expect(find.byKey(const Key('exercise-question')), findsNothing);
    expect(find.text(first.title), findsOneWidget);
    expect(
      find.byKey(const Key('story-picture-placeholder')),
      findsOneWidget,
      reason:
          'no Cloud Storage in tests: the placeholder, never a broken image',
    );
    await playStory(
      tester,
      first,
      optionId: otherOf(first),
      feedbackKey: 'feedback-incorrect',
    );
    expect(find.text('いちばんよい選択'), findsOneWidget);
    expect(
      textOf(tester, 'feedback-incorrect'),
      contains(first.options.firstWhere((o) => o.id == bestOf(first)).text),
    );
    expect(find.text('この問題は、レッスンの最後にもう一度出るよ'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget, reason: 'review queued');
    await tapKey(tester, 'lesson-next');

    await playStory(
      tester,
      second,
      optionId: bestOf(second),
      feedbackKey: 'feedback-correct',
    );
    await tapKey(tester, 'lesson-next');
    await playStory(
      tester,
      third,
      optionId: bestOf(third),
      feedbackKey: 'feedback-correct',
    );
    await tapKey(tester, 'lesson-next');

    // The review: skipping straight to the choice, answered right.
    expect(find.byKey(const Key('review-badge')), findsOneWidget);
    await playStory(
      tester,
      first,
      optionId: bestOf(first),
      feedbackKey: 'feedback-correct',
      skip: true,
    );
    expect(find.byKey(const Key('feedback-explanation')), findsOneWidget);
    await tapKey(tester, 'lesson-next');

    expect(find.text('レッスンクリア！'), findsOneWidget);
    expect(textOf(tester, 'result-correct'), contains('2 / 3 もん'));
    expect(setup.api.completed, {StoryFixture.lessonId});
    expect(setup.api.answerBodies.map((b) => b['answer']), [
      {'type': 'story', 'optionId': otherOf(first)},
      {'type': 'story', 'optionId': bestOf(second)},
      {'type': 'story', 'optionId': bestOf(third)},
      {'type': 'story', 'optionId': bestOf(first)},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed send keeps the choice and can be sent again', (
    tester,
  ) async {
    final setup = storyFixture.setup();
    final first = storyFixture.exercises.first;
    await pumpApp(tester, api: setup.api, content: setup.content);
    await openLesson(tester, StoryFixture.lessonId);
    setup.api.failNext('/v1/answers', Exception('offline'));

    await tapKey(tester, 'story-skip');
    await tapKey(tester, 'choice-option-${bestOf(first)}');
    await tapKey(tester, 'lesson-check');
    expect(find.byKey(const Key('lesson-submit-error')), findsOneWidget);
    expect(find.text('もう一度送る'), findsOneWidget);

    await tapKey(tester, 'lesson-check');
    expect(
      find.text('そのあと 1 / ${outcomeLength(first, bestOf(first))}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the scene also moves on', (tester) async {
    final setup = storyFixture.setup();
    final first = storyFixture.exercises.first;
    await pumpApp(tester, api: setup.api, content: setup.content);
    await openLesson(tester, StoryFixture.lessonId);

    await tester.tap(find.text(first.scenes[0].text));
    await tester.pumpAndSettle();

    expect(find.text(first.scenes[1].text), findsOneWidget);
    expect(find.text('場面 2 / ${first.scenes.length}'), findsOneWidget);
  });
}
