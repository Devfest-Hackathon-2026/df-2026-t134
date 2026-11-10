import '../support/answer_selection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/hallucination_flow_test.dart' as hallucination;
import '../features/lesson/lesson_flow_test.dart' as flow;

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('hallucination exercise stays usable at $width and 200% text', (
      tester,
    ) async {
      final setup = hallucination.hallucinationLesson(position: 0);
      await flow.pumpApp(tester, api: setup.api, content: setup.content);
      tester.view.physicalSize = Size(width, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await flow.openLesson(tester, 'u1-l1');

      // A false alarm and a miss, so every kind of feedback is laid out.
      await toggleAnswerSentence(tester, 'hallucination', 4);
      await toggleAnswerSentence(tester, 'hallucination', 0);
      await flow.checkAndExpect(tester, 'feedback-incorrect');
      for (final key in [
        'hallucination-feedback-error-1',
        'hallucination-feedback-error-4',
        'hallucination-feedback-false-alarm-0',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(Key(key)),
          120,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await flow.tapKey(tester, 'lesson-next');
      expect(find.byKey(const Key('exercise-u1-l1-q1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
