// Opt-in visual review, rendering the same bundled font as production.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lesson/lesson_flow_test.dart' as flow;
import '../features/lesson/live_check_flow_test.dart' as live;
import '../support/answer_selection.dart';
import '../support/fakes.dart';
import '../support/live_check_lesson.dart' as fixture;

import 'package:ailearn/models/answer_mark.dart';

void main() {
  testWidgets('capture answer verification', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('WDXL Lubrifont JP N')..addFont(
            rootBundle.load('assets/fonts/wdxl/WDXLLubrifontJPN-Regular.ttf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: buildTestApp(
          auth: FakeAuthRepository(initialUser: flow.learner),
          profiles: FakeProfileRepository({'google-user': sampleProfile}),
          content: fixture.LiveCheckLessonFixture.content(),
          api: fixture.LiveCheckLessonFixture.api(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await live.reachLiveCheck(tester);
    await live.tapInExercise(tester, 'live-check-suggestion-0');
    await flow.tapKey(tester, 'live-check-send');
    await selectAnswerRange(tester, 'live-check', const AnswerMark(8, 12));
    await tapAnswerControl(tester, 'live-check-mark-selected');
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/capture/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.ensureVisible(find.byKey(const Key('live-check-answer')));
    await capture('answer-desktop');
    tester.view.physicalSize = const Size(360, 1000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('live-check-answer')));
    await capture('answer-mobile');
    await tapAnswerControl(tester, 'live-check-no-errors');
    await capture('answer-no-errors');
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));
}
