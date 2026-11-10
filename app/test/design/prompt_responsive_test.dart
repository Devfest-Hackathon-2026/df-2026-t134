import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/lesson_flow_test.dart' as flow;
import '../features/lesson/prompt_lesson_flow_test.dart' as prompt;
import '../support/fake_api.dart';
import '../support/prompt_lesson.dart';

Future<void> pumpAt(
  WidgetTester tester,
  double width,
  FakeLearningApi api,
) async {
  await flow.pumpApp(tester, api: api, content: PromptLessonFixture.content());
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('the prompt exercise is usable at $width and 200% text', (
      tester,
    ) async {
      final api = PromptLessonFixture.api();
      await pumpAt(tester, width, api);

      await prompt.playPromptLesson(tester, api);

      await flow.tapKey(tester, 'lesson-back-to-path');
      expect(find.text('学習パス'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the AI-off message and skip fit a narrow screen at 200%', (
    tester,
  ) async {
    final api = PromptLessonFixture.api()..promptGradingOn = false;
    await pumpAt(tester, 360, api);
    await prompt.reachPrompt(tester);

    await prompt.write(tester, PromptLessonFixture.goodPrompt);
    await flow.tapKey(tester, 'prompt-send');

    expect(
      find.byKey(const Key('prompt-failure-aiUnavailable')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await flow.tapKey(tester, 'prompt-skip');
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
  });
  testWidgets(
    'keyboard and AI failure preserve the editor and reachable actions',
    (tester) async {
      final api = PromptLessonFixture.api()..promptGradingOn = false;
      await pumpAt(tester, 360, api);
      await prompt.reachPrompt(tester);
      await prompt.write(tester, PromptLessonFixture.goodPrompt);
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await flow.tapKey(tester, 'prompt-send');
      expect(prompt.inputText(tester), PromptLessonFixture.goodPrompt);
      expect(tester.takeException(), isNull);
      await flow.tapKey(tester, 'prompt-skip');
      await tester.scrollUntilVisible(
        find.byKey(const Key('result-not-completed')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
