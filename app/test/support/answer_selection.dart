import 'package:ailearn/features/lesson/widgets/answer_passage.dart';
import 'package:ailearn/models/answer_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapAnswerControl(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<AnswerMark> selectAnswerSentence(
  WidgetTester tester,
  String prefix,
  int index,
) async {
  final finder = find.byKey(Key('$prefix-answer'));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final passage = tester.widget<AnswerPassage>(find.byType(AnswerPassage));
  final mark = sentenceMark(passage.sentences, index);
  await selectAnswerRange(tester, prefix, mark);
  return mark;
}

Future<void> selectAnswerRange(
  WidgetTester tester,
  String prefix,
  AnswerMark mark,
) async {
  final finder = find.byKey(Key('$prefix-answer'));
  await tester.ensureVisible(finder);
  tester.widget<TextField>(finder).controller!.selection = TextSelection(
    baseOffset: mark.start,
    extentOffset: mark.end,
  );
  await tester.pumpAndSettle();
}

Future<void> toggleAnswerSentence(
  WidgetTester tester,
  String prefix,
  int index,
) async {
  final mark = await selectAnswerSentence(tester, prefix, index);
  final chip = find.byKey(Key('$prefix-mark-${mark.start}-${mark.end}'));
  if (chip.evaluate().isNotEmpty) {
    final remove = find.descendant(
      of: chip,
      matching: find.byTooltip('この指定を取り消す'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
  } else {
    await tapAnswerControl(tester, '$prefix-mark-selected');
  }
}

Future<void> lookupAnswerSentence(WidgetTester tester, int index) async {
  await selectAnswerSentence(tester, 'live-check', index);
  await tapAnswerControl(tester, 'live-check-lookup-selected');
}
