import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_api.dart';
import '../../support/prompt_lesson.dart';
import 'lesson_controller_test.dart' show Harness;

typedef F = PromptLessonFixture;

/// The prompt lesson started and its first (choice) exercise answered, so
/// the prompt exercise is current.
Future<Harness> atPrompt() async {
  final h = Harness(F.lessonId, content: F.content(), api: F.api());
  await h.start();
  h.controller.selectOption('b');
  await h.controller.check();
  await h.controller.next();
  expect(h.playing.draft, isA<PromptDraft>());
  return h;
}

PromptDraft draftOf(Harness h) => h.playing.draft as PromptDraft;

void main() {
  group('drafts', () {
    test('starts empty with nothing to send', () async {
      final h = await atPrompt();

      expect(draftOf(h).text, isEmpty);
      expect(draftOf(h).promptToSend, isNull);
      expect(draftOf(h).toAnswer(), isNull, reason: 'not a /v1/answers type');
      expect(h.controller.evaluatePrompt, throwsStateError);
      expect(h.controller.check, throwsStateError);
    });

    test('sends the trimmed text; blank or too long text is not sendable', () {
      final draft = PromptDraft(F.prompt);

      expect(draft.edit('  \n ').promptToSend, isNull);
      expect(draft.edit('  場所を 3 つ\n').promptToSend, '場所を 3 つ');
      final max = F.prompt.maxLength;
      expect(draft.edit('あ' * max).promptToSend, hasLength(max));
      expect(draft.edit('あ' * (max + 1)).isTooLong, isTrue);
      expect(draft.edit('あ' * (max + 1)).promptToSend, isNull);
    });

    test('editing a draft of another type is a bug', () async {
      final h = Harness(F.lessonId, content: F.content(), api: F.api());
      await h.start();

      expect(() => h.controller.editPrompt('x'), throwsStateError);
    });
  });

  group('grading', () {
    test('evaluated: shows the scores, records XP and moves on', () async {
      final h = await atPrompt();
      h.controller.editPrompt('  ${F.goodPrompt}  ');

      await h.controller.evaluatePrompt();

      expect(h.api.promptBodies.single, {
        'exerciseId': F.promptId,
        'prompt': F.goodPrompt,
      });
      final checked = h.playing.status as PromptChecked;
      expect(checked.evaluation.total, 7);
      expect(h.playing.isEditable, isFalse);
      expect(h.playing.progress, 1, reason: 'the graded step counts as done');
      expect(h.playing.steps, hasLength(2), reason: 'never queued for review');
      expect(h.playing.tally.firstTryCorrect, 2);
      expect(h.playing.tally.xpGained, 20);

      h.controller.editPrompt('changed');
      expect(draftOf(h).text, '  ${F.goodPrompt}  ', reason: 'read-only now');

      await h.controller.next();

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonCompleted>());
      expect(finished.xpGained, 40, reason: 'two answers and the bonus');
      expect(h.api.completed, {F.lessonId});
    });

    test('a low total is not a pass and earns no XP', () async {
      final h = await atPrompt();
      h.api.promptTotal = 3;
      h.controller.editPrompt('場所を教えて');

      await h.controller.evaluatePrompt();

      final evaluation = (h.playing.status as PromptChecked).evaluation;
      expect(evaluation.passed, isFalse);
      expect(h.playing.tally.firstTryCorrect, 1);
      expect(h.playing.steps, hasLength(2));
      await h.controller.next();
      expect(
        (h.state as LessonFinished).outcome,
        isA<LessonCompleted>(),
        reason: 'a graded prompt is an attempt',
      );
    });

    test('blocked: back to editing with the text and the message', () async {
      final h = await atPrompt();
      const text = '090-1234-5678 のお父さんと出かけたい';
      h.controller.editPrompt(text);

      await h.controller.evaluatePrompt();

      expect(h.playing.status, isA<Answering>());
      expect(h.playing.isEditable, isTrue);
      expect(draftOf(h).text, text);
      final blocked = draftOf(h).blocked!;
      expect(blocked.reasons, [PromptBlockReason.personalInfo]);
      expect(h.playing.tally.xpGained, 10, reason: 'nothing recorded');

      h.controller.editPrompt('お父さんと出かけたい');
      expect(draftOf(h).blocked, same(blocked), reason: 'kept while editing');

      await h.controller.evaluatePrompt();

      expect(h.playing.status, isA<PromptChecked>());
      expect(draftOf(h).blocked, isNull);
      expect(h.api.promptBodies, hasLength(2));
    });

    test('a request in flight ignores edits and a second send', () async {
      final h = await atPrompt();
      h.controller.editPrompt(F.goodPrompt);

      final sending = h.controller.evaluatePrompt();
      expect(h.playing.status, isA<Submitting>());
      h.controller.editPrompt('changed');
      await h.controller.evaluatePrompt();
      await sending;

      expect(h.api.promptBodies, hasLength(1));
      expect(draftOf(h).text, F.goodPrompt);
    });
  });

  group('failures', () {
    test('AI grading off (503): retry later or skip', () async {
      final h = await atPrompt();
      h.api.promptGradingOn = false;
      h.controller.editPrompt(F.goodPrompt);

      await h.controller.evaluatePrompt();

      final failed = h.playing.status as SubmitFailed;
      expect(
        (failed.error as ApiException).code,
        ApiErrorCode.upstreamUnavailable,
      );
      expect(draftOf(h).text, F.goodPrompt);

      h.api.promptGradingOn = true;
      await h.controller.evaluatePrompt();
      expect(h.playing.status, isA<PromptChecked>(), reason: 'retry works');
    });

    test('skipping after 503 ends the lesson as not completed', () async {
      final h = await atPrompt();
      h.api.promptGradingOn = false;
      h.controller.editPrompt(F.goodPrompt);
      await h.controller.evaluatePrompt();

      await h.controller.skipPrompt();

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonNotCompleted>());
      expect(finished.tally.skipped, 1);
      expect(finished.xpGained, 10);
      expect(h.api.completed, isEmpty);
    });

    test('daily limit (429): skip moves on', () async {
      final h = await atPrompt();
      h.api.failNext(
        '/v1/prompt/evaluate',
        FakeLearningApi.errorResponse(429, 'rate_limited'),
      );
      h.controller.editPrompt(F.goodPrompt);

      await h.controller.evaluatePrompt();

      final failed = h.playing.status as SubmitFailed;
      expect((failed.error as ApiException).code, ApiErrorCode.rateLimited);
      await h.controller.skipPrompt();
      expect(h.state, isA<LessonFinished>());
    });

    test('a network error keeps the text and the retry sends it', () async {
      final h = await atPrompt();
      h.api.failNext('/v1/prompt/evaluate', http.ClientException('offline'));
      h.controller.editPrompt(F.goodPrompt);

      await h.controller.evaluatePrompt();

      expect(h.playing.status, isA<SubmitFailed>());
      expect(h.playing.isEditable, isTrue);
      expect(draftOf(h).text, F.goodPrompt);

      await h.controller.evaluatePrompt();

      expect(h.playing.status, isA<PromptChecked>());
      expect(h.api.promptBodies.first, h.api.promptBodies.last);
    });

    test('skipping is only for a prompt that could not be graded', () async {
      final h = await atPrompt();

      expect(h.controller.skipPrompt, throwsStateError);
      h.controller.editPrompt(F.goodPrompt);
      expect(h.controller.skipPrompt, throwsStateError);
    });
  });
}
