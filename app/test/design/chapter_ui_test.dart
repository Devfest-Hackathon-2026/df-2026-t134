import 'package:ailearn/data/repositories.dart';
import 'package:ailearn/design/chapter_theme.dart';
import 'package:ailearn/design/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const learner = AppUser(uid: 'ui-user', isAnonymous: true);
FakeContentRepository chapters() => FakeContentRepository(
  units: [
    unit('u1', 1, title: 'AI ってなに？'),
    unit('u2', 2, title: 'プロンプトの基本'),
    unit('u3', 3, title: 'ハルシネーションを見抜く'),
  ],
  lessons: [
    lesson('u1-l1', 'u1', 1, title: 'AI は予測マシン'),
    lesson('u1-l2', 'u1', 2, title: '得意と不得意'),
    lesson('u2-l1', 'u2', 1, title: 'ことばを組み立てよう'),
    lesson('u3-l1', 'u3', 1, title: '本当かな？を見つけよう'),
  ],
);
Widget ready() => buildTestApp(
  auth: FakeAuthRepository(initialUser: learner),
  profiles: FakeProfileRepository({'ui-user': sampleProfile}),
  content: chapters(),
);
Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all chapters remain accessible at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(ready());
        await tester.pumpAndSettle();
        for (final key in ['path-xp', 'path-streak']) {
          expect(
            find.ancestor(
              of: find.byKey(Key(key)),
              matching: find.byKey(const Key('path-top-bar')),
            ),
            findsOneWidget,
          );
        }
        if (scale == 1) {
          expect(
            tester.getTopLeft(find.byKey(const Key('unit-pager'))).dy,
            lessThan(200),
          );
        }

        expect(tester.takeException(), isNull);
        await tap(tester, 'lesson-u1-l2-locked');
        await tester.ensureVisible(find.byKey(const Key('path-start-lesson')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('path-start-lesson')))
              .onPressed,
          isNull,
        );
        expect(find.text('前のレッスンをクリアするとひらきます'), findsOneWidget);
        await tap(tester, 'unit-next');
        expect(find.text('AIの創作スタジオ'), findsOneWidget);
        await tap(tester, 'unit-next');
        expect(find.text('冒険する学習ワールド'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('unit-next')))
              .onPressed,
          isNull,
        );
        await tap(tester, 'unit-tab-u1');
        expect(find.byKey(const Key('lesson-detail-u1-l2')), findsOneWidget);
        expect(find.text('1 / 3 ユニット'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets('login and onboarding scroll at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(buildTestApp(auth: FakeAuthRepository()));
        await tester.pumpAndSettle();
        await tap(tester, 'login-guest');
        await tester.ensureVisible(
          find.byKey(const Key('onboarding-nickname')),
        );
        await tester.enterText(
          find.byKey(const Key('onboarding-nickname')),
          'ひかり',
        );
        await tap(tester, 'onboarding-grade-j1');
        await tester.ensureVisible(find.byKey(const Key('onboarding-submit')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('onboarding-submit'))).bottom,
          lessThanOrEqualTo(900),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('motion respects setting, OS, hidden pages and lifecycle', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget scene({
      bool enabled = true,
      bool osReduced = false,
      double keyboard = 0,
    }) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ailearnTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: osReduced,
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: TickerMode(enabled: enabled, child: const AmbientMotif()),
        ),
      ),
    );
    await tester.pumpWidget(scene());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    container.read(reducedMotionProvider.notifier).setReduced(true);
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    container.read(reducedMotionProvider.notifier).setReduced(false);
    await tester.pumpWidget(scene(osReduced: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(scene(keyboard: 320));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(scene(enabled: false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(scene());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('chapter palettes and body colors maintain readable contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
    }

    for (final id in ['u1', 'u2', 'u3', 'future']) {
      final palette = ChapterPalette.forUnit(id);
      expect(contrast(palette.accent, Colors.white), greaterThanOrEqualTo(4.5));
      expect(
        contrast(ChapterPalette.ink, palette.wash),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(ChapterPalette.muted, ChapterPalette.background),
      greaterThanOrEqualTo(4.5),
    );
  });
}
