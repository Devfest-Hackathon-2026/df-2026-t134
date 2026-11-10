import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/lesson_flow_test.dart' as flow;

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('lesson completion remains usable at $width and 200% text', (
      tester,
    ) async {
      await flow.pumpApp(tester, api: flow.unit1Api());
      tester.view.physicalSize = Size(width, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await flow.openLesson(tester, 'u1-l1');
      await flow.tapKey(tester, 'choice-option-b');
      await flow.checkAndExpect(tester, 'feedback-correct');
      await flow.tapKey(tester, 'lesson-next');
      await flow.playRestOfLesson1(tester);
      expect(find.text('レッスンクリア！'), findsOneWidget);
      await flow.tapKey(tester, 'lesson-back-to-path');
      expect(find.text('学習パス'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
