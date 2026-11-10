import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/lesson_flow_test.dart' as flow;
import '../features/lesson/story_flow_test.dart' as story;
import '../support/story.dart';

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('story player stays usable at $width and 200% text', (
      tester,
    ) async {
      final setup = storyFixture.setup();
      final first = storyFixture.exercises.first;
      await flow.pumpApp(tester, api: setup.api, content: setup.content);
      tester.view.physicalSize = Size(width, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await flow.openLesson(tester, StoryFixture.lessonId);

      // Every scene, the choice, the whole outcome and the feedback.
      await story.playStory(
        tester,
        first,
        optionId: story.otherOf(first),
        feedbackKey: 'feedback-incorrect',
      );
      // The action panel keeps to at most 55% of the body's height.
      final panel = tester.getSize(
        find.byKey(const Key('lesson-action-scroll')),
      );
      expect(panel.height, lessThanOrEqualTo(900 * .55));
      await flow.tapKey(tester, 'lesson-next');
      expect(find.text(storyFixture.exercises[1].title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
