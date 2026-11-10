import 'dart:convert';
import 'dart:io';

import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/answer_mark.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/answer_selection.dart';
import '../../support/fake_api.dart';
import '../../support/hallucination.dart';
import '../../support/live_check_lesson.dart';
import 'lesson_flow_test.dart' as flow;
import 'live_check_flow_test.dart' as live;

void main() {
  test(
    'clean content is valid and no-error judgment differs from no answer',
    () {
      final json = jsonDecode(
        File('test/fixtures/hallucination.json').readAsStringSync(),
      ) as Map;
      final exercise = Exercise.fromJson({
        ...json['exercise'] as Map,
        'errorCount': 0,
      }) as HallucinationExercise;
      final initial = HallucinationDraft(exercise);
      expect(initial.toAnswer(), isNull);
      final clean = initial.confirmNoErrors();
      expect(
        (clean.toAnswer() as HallucinationAnswer).sentenceIndexes,
        isEmpty,
      );
      final bounds = sentenceMark(exercise.sentences, 1);
      final marked = clean.withMarks([
        AnswerMark(bounds.start + 1, bounds.start + 4),
      ]);
      expect(marked.confirmedNoErrors, isFalse);
      expect(marked.selectedIndexes, {1});
      expect(marked.withMarks([]).toAnswer(), isNull);
    },
  );

  test(
    'marks retain offsets for repeated text, overlap and crossed claims',
    () {
      const sentences = [
        Sentence(index: 0, text: '同じ言葉。'),
        Sentence(index: 1, text: '同じ言葉。'),
      ];
      final second = sentenceMark(sentences, 1);
      expect(
        markedIndexes(sentences, [AnswerMark(second.start, second.start + 2)]),
        {1},
      );
      expect(markedIndexes(sentences, [AnswerMark(2, second.start + 2)]), {
        0,
        1,
      });
      final draft = HallucinationDraft(hallucinationFixture.exercise)
          .withMarks([const AnswerMark(0, 3), const AnswerMark(1, 4)]);
      expect(draft.withMarks([const AnswerMark(1, 4)]).selectedIndexes, {0});
      expect(
        () => markedIndexes(sentences, [const AnswerMark(0, 1000)]),
        throwsArgumentError,
      );
    },
  );

  for (final width in [360.0, 1366.0]) {
    testWidgets(
      'a clean live answer can be judged and completed at $width / 200%',
      (tester) async {
        final api = LiveCheckLessonFixture.api();
        api.liveCheckAnswer = FakeLiveCheckAnswer(
          sentences: [
            LiveCheckLessonFixture.correction,
            ...LiveCheckLessonFixture.answer.sentences.skip(1),
          ],
          errors: const [],
          sources: LiveCheckLessonFixture.answer.sources,
        );
        await flow.pumpApp(
          tester,
          api: api,
          content: LiveCheckLessonFixture.content(),
        );
        tester.view.physicalSize = Size(width, 900);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await live.reachLiveCheck(tester);
        await live.tapInExercise(tester, 'live-check-suggestion-0');
        await flow.tapKey(tester, 'live-check-send');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('live-check-submit')))
              .onPressed,
          isNull,
        );
        final answer = tester
            .widget<TextField>(find.byKey(const Key('live-check-answer')))
            .controller!
            .text;
        await selectAnswerRange(
          tester,
          'live-check',
          AnswerMark(0, answer.length),
        );
        await tapAnswerControl(tester, 'live-check-mark-selected');
        expect(tester.takeException(), isNull);
        expect(find.byType(InputChip), findsOneWidget);
        await tapAnswerControl(tester, 'live-check-no-errors');
        await flow.tapKey(tester, 'live-check-submit');
        expect(find.byKey(const Key('feedback-correct')), findsOneWidget);
        expect(find.textContaining('誤りはありません'), findsWidgets);
        await flow.tapKey(tester, 'lesson-next');
        expect(find.text('レッスンクリア！'), findsOneWidget);
        expect(api.completed, contains(LiveCheckLessonFixture.lessonId));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
