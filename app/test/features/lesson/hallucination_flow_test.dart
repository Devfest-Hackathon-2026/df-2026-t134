import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import '../../support/fakes.dart';
import '../../support/hallucination.dart';
import 'lesson_flow_test.dart'
    show checkAndExpect, openLesson, playRestOfLesson1, pumpApp, tapKey, textOf;

/// u1-l1 with the hallucination fixture at [position], and its fake API.
({FakeContentRepository content, FakeLearningApi api}) hallucinationLesson({
  required int position,
}) {
  final lesson = hallucinationFixture.lessonU1L1(position: position);
  return (
    content: FakeContentRepository(
      units: [unit('u1', 1)],
      lessons: hallucinationFixture.unit1Lessons(position: position),
      exercises: hallucinationFixture.unit1Exercises,
    ),
    api: FakeLearningApi(
      answerKeys: hallucinationFixture.answerKeys,
      lessonExercises: {lesson.id: lesson.exerciseIds},
    ),
  );
}

bool checkEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('lesson-check')))
        .onPressed !=
    null;

void main() {
  testWidgets('plays a hallucination exercise, its review and the result', (
    tester,
  ) async {
    final setup = hallucinationLesson(position: 1);
    await pumpApp(tester, api: setup.api, content: setup.content);
    await openLesson(tester, 'u1-l1');
    expect(find.text('0 / 7'), findsOneWidget);

    await tapKey(tester, 'choice-option-b');
    await checkAndExpect(tester, 'feedback-correct');
    await tapKey(tester, 'lesson-next');

    // The hallucination exercise: nothing tapped yet, so no check.
    expect(find.text('AI の答え：富士山'), findsOneWidget);
    expect(find.text('まちがいは 2 こ'), findsOneWidget);
    expect(checkEnabled(tester), isFalse);
    expect(find.text('まちがっていると思う文をタップしてからチェックしよう'), findsOneWidget);
    await tapKey(tester, 'hallucination-sentence-2');
    expect(checkEnabled(tester), isTrue);
    await tapKey(tester, 'hallucination-sentence-2');
    expect(checkEnabled(tester), isFalse, reason: 'tapping again unmarks');
    await tapKey(tester, 'hallucination-sentence-0');
    await tapKey(tester, 'hallucination-sentence-4');
    expect(find.text('えらんだ文：2 こ'), findsOneWidget);

    await checkAndExpect(tester, 'feedback-incorrect');
    expect(find.text('おしい！'), findsOneWidget);
    expect(find.text('まちがい 2 こ中 1 こ見つけたよ'), findsOneWidget);
    expect(
      find.byKey(const Key('hallucination-feedback-false-alarm-0')),
      findsOneWidget,
    );
    expect(textOf(tester, 'hallucination-feedback-error-1'), contains('見のがし'));
    expect(
      textOf(tester, 'hallucination-feedback-error-1'),
      contains('正しくは：高さは 3776 メートルです。'),
    );
    expect(textOf(tester, 'hallucination-feedback-error-4'), contains('見つけた！'));
    expect(find.text('2 / 8'), findsOneWidget, reason: 'review queued');
    expect(setup.api.answerBodies.last['answer'], {
      'type': 'hallucination',
      'sentenceIndexes': [0, 4],
    });
    await tapKey(tester, 'lesson-next');

    await playRestOfLesson1(tester);

    // The review: a fresh draft, answered right this time.
    expect(find.byKey(const Key('review-badge')), findsOneWidget);
    expect(find.text('えらんだ文：0 こ'), findsOneWidget);
    await tapKey(tester, 'hallucination-sentence-1');
    await tapKey(tester, 'hallucination-sentence-4');
    await checkAndExpect(tester, 'feedback-correct');
    expect(find.text('まちがい 2 こ中 2 こ見つけたよ'), findsOneWidget);
    await tapKey(tester, 'lesson-next');

    expect(find.text('レッスンクリア！'), findsOneWidget);
    expect(textOf(tester, 'result-correct'), contains('6 / 7 もん'));
    expect(textOf(tester, 'result-xp-gained'), contains('+90 XP'));
    expect(setup.api.completed, {'u1-l1'});
    expect(tester.takeException(), isNull);
  });
}
