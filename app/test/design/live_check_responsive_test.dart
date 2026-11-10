import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/lesson_flow_test.dart' as flow;
import '../features/lesson/live_check_flow_test.dart' as live;
import '../support/fake_api.dart';
import '../support/live_check_lesson.dart';

Future<void> pumpAt(
  WidgetTester tester,
  double width,
  FakeLearningApi api,
) async {
  await flow.pumpApp(
    tester,
    api: api,
    content: LiveCheckLessonFixture.content(),
  );
  tester.view.physicalSize = Size(width, 900);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('the live check is playable at $width and 200% text', (
      tester,
    ) async {
      final api = LiveCheckLessonFixture.api();
      await pumpAt(tester, width, api);

      await live.playLiveCheck(tester, api);

      await flow.tapKey(tester, 'lesson-back-to-path');
      expect(find.text('学習パス'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('with the keyboard open the question and actions stay usable', (
    tester,
  ) async {
    final api = LiveCheckLessonFixture.api()..liveCheckAnswer = null;
    await pumpAt(tester, 360, api);
    await live.reachLiveCheck(tester);
    await live.write(tester, '富士山はどうやってできたの？');
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await flow.tapKey(tester, 'live-check-send');

    expect(live.inputText(tester), '富士山はどうやってできたの？');
    expect(
      find.byKey(const Key('live-check-failure-aiUnavailable')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await flow.tapKey(tester, 'live-check-skip');
    await tester.scrollUntilVisible(
      find.byKey(const Key('result-not-completed')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('result-not-completed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('looked-up sources fit under the sentence on a narrow screen', (
    tester,
  ) async {
    final api = LiveCheckLessonFixture.api();
    await pumpAt(tester, 360, api);
    await live.reachLiveCheck(tester);
    await live.tapInExercise(tester, 'live-check-suggestion-0');
    await flow.tapKey(tester, 'live-check-send');

    await live.tapInExercise(tester, 'live-check-lookup-2');
    await live.showInExercise(tester, 'live-check-sources-2');

    final card = tester.getRect(find.byKey(const Key('live-check-sentence-2')));
    final sources = tester.getRect(
      find.byKey(const Key('live-check-sources-2')),
    );
    expect(card.contains(sources.center), isTrue);
    expect(sources.width, lessThanOrEqualTo(360));
    expect(find.text('pref.yamanashi.jp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
