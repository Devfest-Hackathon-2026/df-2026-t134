import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/live_check.dart';
import 'package:ailearn/models/prompt_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_api.dart';
import '../../support/live_check_lesson.dart';
import 'lesson_controller_test.dart' show Harness;

typedef F = LiveCheckLessonFixture;

/// The lesson started and its choice exercise answered, so the live check is
/// current.
Future<Harness> atLiveCheck({FakeLearningApi? api}) async {
  final h = Harness(F.lessonId, content: F.content(), api: api ?? F.api());
  await h.start();
  h.controller.selectOption('b');
  await h.controller.check();
  await h.controller.next();
  expect(h.playing.draft, isA<LiveCheckDraft>());
  return h;
}

LiveCheckDraft draftOf(Harness h) => h.playing.draft as LiveCheckDraft;

Future<Harness> started({FakeLearningApi? api}) async {
  final h = await atLiveCheck(api: api);
  h.controller.editLiveCheckPrompt('  ${F.liveCheck.suggestions.first}\n');
  await h.controller.startLiveCheck();
  expect(draftOf(h).session, isNotNull);
  return h;
}

void main() {
  group('composing', () {
    test(
      'starts empty; only a trimmed prompt within the limit is sent',
      () async {
        final h = await atLiveCheck();
        final draft = draftOf(h);

        expect(draft.isComposing, isTrue);
        expect(draft.toAnswer(), isNull);
        expect(h.controller.startLiveCheck, throwsStateError);
        expect(draft.edit(' \n').promptToSend, isNull);
        expect(draft.edit(' 高さは？ ').promptToSend, '高さは？');
        expect(draft.edit('あ' * 201).isTooLong, isTrue);
        expect(draft.edit('あ' * 201).promptToSend, isNull);
      },
    );

    test('the answer arrives with the sentences and the lookups', () async {
      final h = await started();
      final draft = draftOf(h);

      expect(h.api.liveCheckBodies.single, {
        'exerciseId': F.liveId,
        'prompt': F.liveCheck.suggestions.first,
      });
      expect(draft.session!.sentences.first.text, F.answer.sentences.first);
      expect(draft.lookupsLeft, 2);
      expect(draft.text.trim(), F.liveCheck.suggestions.first);
      expect(h.playing.status, isA<Answering>());
      expect(() => draft.edit('x'), throwsStateError, reason: 'sent already');
    });

    test(
      'blocked keeps the text with the message and records nothing',
      () async {
        final h = await atLiveCheck();
        h.controller.editLiveCheckPrompt(
          'おすすめの${FakeLearningApi.offTopicWord}は？',
        );

        await h.controller.startLiveCheck();

        final draft = draftOf(h);
        expect(draft.isComposing, isTrue);
        expect(draft.blocked!.reasons, [PromptBlockReason.offTopic]);
        expect(draft.text, contains(FakeLearningApi.offTopicWord));
        expect(h.api.liveCheckSessions, isEmpty);
        // Editing keeps the message until the prompt is sent again.
        h.controller.editLiveCheckPrompt('富士山の高さは？');
        expect(draftOf(h).blocked, isNotNull);
        await h.controller.startLiveCheck();
        expect(draftOf(h).blocked, isNull);
        expect(draftOf(h).session, isNotNull);
      },
    );

    for (final (name, failure, code) in [
      (
        'AI off',
        FakeLearningApi.errorResponse(503, 'upstream_unavailable'),
        ApiErrorCode.upstreamUnavailable,
      ),
      (
        'daily limit',
        FakeLearningApi.errorResponse(429, 'rate_limited'),
        ApiErrorCode.rateLimited,
      ),
    ]) {
      test('$name fails with the text kept and can be skipped', () async {
        final api = F.api()..failNext('/v1/live-checks', failure);
        final h = await atLiveCheck(api: api);
        h.controller.editLiveCheckPrompt('富士山の高さは？');

        await h.controller.startLiveCheck();

        final status = h.playing.status as SubmitFailed;
        expect((status.error as ApiException).code, code);
        expect(draftOf(h).text, '富士山の高さは？');
        await h.controller.skipLiveCheck();
        expect(h.state, isA<LessonFinished>());
        expect((h.state as LessonFinished).tally.skipped, 1);
        expect((h.state as LessonFinished).outcome, isA<LessonNotCompleted>());
      });
    }

    test('a network error can be retried', () async {
      final api = F.api()
        ..failNext('/v1/live-checks', http.ClientException('offline'));
      final h = await atLiveCheck(api: api);
      h.controller.editLiveCheckPrompt('富士山の高さは？');

      await h.controller.startLiveCheck();
      expect(h.playing.status, isA<SubmitFailed>());
      await h.controller.startLiveCheck();

      expect(draftOf(h).session, isNotNull);
    });

    test('skipping is only for a live check that failed', () async {
      final h = await atLiveCheck();

      expect(h.controller.skipLiveCheck, throwsStateError);
    });
  });

  group('investigating', () {
    test(
      'a lookup returns the sources and counts down; again is free',
      () async {
        final h = await started();

        final first = await h.controller.lookUpSentence(0);
        final again = await h.controller.lookUpSentence(0);

        expect(first, [
          const WebSource(
            title: 'fuji-net.co.jp',
            uri: 'https://example.jp/fuji',
          ),
        ]);
        expect(again, first);
        expect(h.api.lookupIndexes, [0], reason: 'asked the server once');
        expect(draftOf(h).lookupsLeft, 1);
        expect(draftOf(h).lookups.keys, [0]);
      },
    );

    test('a sentence without sources still uses a lookup', () async {
      final h = await started();

      expect(await h.controller.lookUpSentence(1), isEmpty);
      expect(draftOf(h).lookupsLeft, 1);
    });

    test('no lookups are asked for once they are used up', () async {
      final h = await started();
      await h.controller.lookUpSentence(0);
      await h.controller.lookUpSentence(1);

      expect(await h.controller.lookUpSentence(2), isNull);
      expect(h.api.lookupIndexes, [0, 1]);
      expect(draftOf(h).canLookUp(2), isFalse);
    });

    test('a 409 from the server means none are left', () async {
      final h = await started();
      // The server's count wins over the one the answer came with.
      h.api.liveCheckLookupLimit = 0;
      expect(await h.controller.lookUpSentence(0), isNull);

      final draft = draftOf(h);
      expect(draft.lookupFailure, (index: 0, failure: LookupFailure.noneLeft));
      expect(draft.lookupsLeft, 0);
    });

    test('a failed lookup can be tried again', () async {
      final h = await started();
      h.api.failNext(
        '/v1/live-checks/session1/lookup',
        http.ClientException('offline'),
      );

      expect(await h.controller.lookUpSentence(0), isNull);
      expect(draftOf(h).lookupFailure?.failure, LookupFailure.failed);
      expect(draftOf(h).lookupsLeft, 2);
      expect(await h.controller.lookUpSentence(0), isNotEmpty);
      expect(draftOf(h).lookupFailure, isNull);
    });

    test('marks are needed before the answer can be sent', () async {
      final h = await started();

      expect(draftOf(h).toAnswer(), isNull);
      h.controller.toggleLiveCheckSentence(2);
      h.controller.toggleLiveCheckSentence(0);
      h.controller.toggleLiveCheckSentence(2);

      final answer = draftOf(h).toAnswer()!;
      expect(answer.toJson(), {
        'type': 'live_check',
        'sessionId': 'session1',
        'sentenceIndexes': [0],
      });
      expect(
        () => h.controller.toggleLiveCheckSentence(9),
        throwsArgumentError,
      );
    });
  });

  group('checking', () {
    test('found: correct with XP, the review and the sources', () async {
      final h = await started();
      h.controller.toggleLiveCheckSentence(F.wrongIndex);

      await h.controller.check();

      final checked = h.playing.status as Checked;
      expect(checked.response.correct, isTrue);
      expect(checked.response.progress.xpGained, 10);
      final correct = checked.correctAnswer as CorrectLiveCheck;
      final wrong = correct.review.sentences[F.wrongIndex];
      expect(wrong.verdict, SentenceVerdict.found);
      expect(wrong.error!.correction, F.correction);
      expect(correct.sources.map((s) => s.title), [
        'fuji-net.co.jp',
        'pref.yamanashi.jp',
      ]);
      expect(h.playing.steps, hasLength(2), reason: 'nothing to review');
    });

    test('a false alarm is wrong and queues a fresh live check once', () async {
      final h = await started();
      h.controller.toggleLiveCheckSentence(1);

      await h.controller.check();
      final checked = h.playing.status as Checked;
      final review = (checked.correctAnswer as CorrectLiveCheck).review;
      expect(review.sentences[1].verdict, SentenceVerdict.falseAlarm);
      expect(review.sentences[F.wrongIndex].verdict, SentenceVerdict.missed);

      await h.controller.next();
      expect(h.playing.step.isReview, isTrue);
      expect(draftOf(h).isComposing, isTrue, reason: 'a new question');
    });

    test('a failed answer keeps the marks and is sent again', () async {
      final h = await started();
      h.controller.toggleLiveCheckSentence(F.wrongIndex);
      h.api.failNext('/v1/answers', http.ClientException('offline'));

      await h.controller.check();

      expect(h.playing.status, isA<SubmitFailed>());
      expect(draftOf(h).selectedIndexes, {F.wrongIndex});
      await h.controller.check();
      expect(h.playing.status, isA<Checked>());
    });
  });
}
