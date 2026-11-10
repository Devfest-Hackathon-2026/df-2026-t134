// Opt-in visual QA using the same bundled font as production.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import 'chapter_ui_test.dart' as fixtures;

void main() {
  testWidgets('capture chapter UI for visual review', (tester) async {
    await tester.runAsync(() async {
      final bytes = await rootBundle.load(
        'assets/fonts/wdxl/WDXLLubrifontJPN-Regular.ttf',
      );
      for (final family in ['WDXL Lubrifont JP N', 'Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
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

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: buildTestApp(auth: FakeAuthRepository()),
      ),
    );
    await capture('login-desktop');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: fixtures.ready()),
    );
    await capture('lab-desktop');
    await fixtures.tap(tester, 'unit-next');
    await capture('studio-desktop');
    await fixtures.tap(tester, 'unit-next');
    await capture('adventure-desktop');
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    await capture('adventure-mobile');
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));
}
