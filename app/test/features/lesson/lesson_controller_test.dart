import 'dart:convert';

import 'package:ailearn/core/providers.dart';
import 'package:ailearn/data/providers.dart';
import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/features/lesson/lesson_controller.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_api.dart';
import '../../support/fakes.dart';
import '../../support/hallucination.dart';
import '../../support/unit1.dart';

FakeContentRepository unit1Content() =>
    FakeContentRepository(lessons: unit1.lessons, exercises: unit1.exercises);

FakeLearningApi unit1Api() => FakeLearningApi(
  answerKeys: unit1.answerKeys,
  lessonExercises: {for (final l in unit1.lessons) l.id: l.exerciseIds},
);

/// A started lesson with its controller, kept alive by a listener.
class Harness {
  Harness(
    this.lessonId, {
    FakeContentRepository? content,
    FakeLearningApi? api,
    Map<String, Map<String, Object?>>? answerKeys,
  }) : content = content ?? unit1Content(),
       api = api ?? unit1Api(),
       answerKeys = answerKeys ?? unit1.answerKeys {
    container = ProviderContainer.test(
      overrides: [
        contentRepositoryProvider.overrideWithValue(this.content),
        apiClientProvider.overrideWithValue(this.api.client()),
      ],
    );
    container.listen(provider, (_, _) {});
  }

  final String lessonId;
  final FakeContentRepository content;
  final FakeLearningApi api;

  /// Keys [fill] answers from; the same ones the fake API grades with.
  final Map<String, Map<String, Object?>> answerKeys;
  late final ProviderContainer container;

  AsyncNotifierProvider<LessonController, LessonState> get provider =>
      lessonControllerProvider(lessonId);

  LessonController get controller => container.read(provider.notifier);

  Future<LessonState> load() => container.read(provider.future);

  LessonState get state => container.read(provider).requireValue;

  LessonPlaying get playing => state as LessonPlaying;

  Future<void> start() async {
    await load();
    controller.start();
  }

  /// Fills in the current exercise from the answer keys, right or wrong.
  void fill({required bool correct}) {
    final draft = playing.draft;
    final key = answerKeys[draft.exercise.id]!;
    switch (draft) {
      case ChoiceDraft(:final exercise):
        final right = key['correctOptionId']! as String;
        controller.selectOption(
          correct
              ? right
              : exercise.options.firstWhere((o) => o.id != right).id,
        );
      case OrderDraft():
        final order = (key['correctOrder']! as List).cast<String>();
        for (final id in correct ? order : order.reversed) {
          controller.addOrderItem(id);
        }
      case FillBlankDraft(:final exercise):
        final right = (key['correctOptions']! as Map).cast<String, String>();
        for (final (i, blank) in exercise.blanks.indexed) {
          final optionId = correct || i > 0
              ? right[blank.id]!
              : blank.options.firstWhere((o) => o.id != right[blank.id]).id;
          controller.chooseBlankOption(blank.id, optionId);
        }
      case HallucinationDraft(:final exercise):
        final wrong = [
          for (final e in key['errors']! as List)
            (e as Map<String, Object?>)['index']! as int,
        ];
        // Wrong: misses the first error and taps a correct sentence.
        final tapped = correct
            ? wrong
            : [
                ...wrong.skip(1),
                exercise.sentences
                    .firstWhere((s) => !wrong.contains(s.index))
                    .index,
              ];
        tapped.forEach(controller.toggleSentence);
      case PromptDraft():
        throw StateError('write ${draft.exercise.id} with editPrompt');
      case LiveCheckDraft():
        throw StateError('play ${draft.exercise.id} with startLiveCheck');

      case StoryDraft(:final exercise):
        final best = key['bestOptionId']! as String;
        controller.skipStoryScenes();
        controller.selectStoryOption(
          correct ? best : exercise.options.firstWhere((o) => o.id != best).id,
        );
    }
  }

  Future<void> answer({required bool correct}) async {
    fill(correct: correct);
    await controller.check();
  }
}

void main() {
  group('loading', () {
    test('shows the intro with the exercises in lesson order', () async {
      final h = Harness('u1-l1');

      final state = await h.load();

      expect(state, isA<LessonIntro>());
      state as LessonIntro;
      expect(state.lesson.title, 'AI はどうやって文章をつくる？');
      expect(state.exercises.map((e) => e.id), state.lesson.exerciseIds);
    });

    test('a missing or malformed lesson id is "not found"', () async {
      expect(await Harness('u9-l9').load(), isA<LessonNotFound>());
      expect(await Harness('U1 L1').load(), isA<LessonNotFound>());
    });

    test('an exercise of another lesson is broken content', () async {
      final content = unit1Content();
      content.exercises['u1-l1-q1'] = choiceExercise('u1-l1-q1', 'u1-l2');
      final h = Harness('u1-l1', content: content);

      await expectLater(h.load(), throwsFormatException);
      expect(h.container.read(h.provider), isA<AsyncError<LessonState>>());
    });

    test('a missing exercise document is an error', () async {
      final content = unit1Content()..exercises.remove('u1-l1-q3');
      final h = Harness('u1-l1', content: content);

      await expectLater(h.load(), throwsFormatException);
    });
  });

  group('drafts', () {
    test('check is possible only once the answer is complete', () async {
      final h = Harness('u1-l1');
      await h.start();

      expect(h.playing.draft.toAnswer(), isNull);
      expect(h.controller.check, throwsStateError);
      h.controller.selectOption('c');
      expect(h.playing.draft.toAnswer()?.toJson(), {
        'type': 'choice',
        'optionId': 'c',
      });
      expect(() => h.controller.selectOption('zz'), throwsArgumentError);
      expect(() => h.controller.addOrderItem('input'), throwsStateError);
    });

    test('order items are added, removed and undone', () async {
      final h = Harness('u1-l1');
      await h.start();
      for (var i = 0; i < 3; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }
      expect(h.playing.draft, isA<OrderDraft>());

      h.controller
        ..addOrderItem('input')
        ..addOrderItem('predict')
        ..addOrderItem('input')
        ..addOrderItem('append');
      expect((h.playing.draft as OrderDraft).pickedIds, [
        'input',
        'predict',
        'append',
      ]);
      h.controller.removeOrderItem('predict');
      expect((h.playing.draft as OrderDraft).pickedIds, ['input', 'append']);
      h.controller.undoOrderItem();
      expect((h.playing.draft as OrderDraft).pickedIds, ['input']);
      expect(h.playing.draft.toAnswer(), isNull);
    });

    test('fill-in-the-blank needs every blank', () async {
      final h = Harness('u1-l1');
      await h.start();
      await h.answer(correct: true);
      await h.controller.next();
      for (var i = 0; i < 4; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }
      expect(h.playing.step.exercise.id, 'u1-l1-q6');

      h.controller.chooseBlankOption('data', 'a');
      expect(h.playing.draft.toAnswer(), isNull);
      h.controller.chooseBlankOption('pattern', 'c');
      h.controller.chooseBlankOption('pattern', 'b');
      expect(h.playing.draft.toAnswer()?.toJson(), {
        'type': 'fill_blank',
        'selectedOptions': {'data': 'a', 'pattern': 'b'},
      });
    });

    test('the answer cannot change after it is checked', () async {
      final h = Harness('u1-l1');
      await h.start();
      await h.answer(correct: false);

      h.controller.selectOption('b');

      expect((h.playing.draft as ChoiceDraft).selectedOptionId, isNot('b'));
      expect(h.playing.status, isA<Checked>());
      expect(h.api.answerBodies, hasLength(1));
      await h.controller.check(); // ignored, not sent again
      expect(h.api.answerBodies, hasLength(1));
    });
  });

  group('playing', () {
    test('all correct: completes with the bonus and the streak', () async {
      final h = Harness('u1-l1');
      await h.start();

      for (var i = 0; i < 6; i++) {
        expect(h.playing.progress, closeTo(i / 6, 1e-9));
        await h.answer(correct: true);
        final checked = h.playing.status as Checked;
        expect(checked.response.correct, isTrue);
        expect(h.playing.steps, hasLength(6));
        await h.controller.next();
      }

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonCompleted>());
      expect(finished.xpGained, 6 * 10 + 20);
      expect(finished.progress?.xp, 80);
      expect(finished.progress?.streakDays, 1);
      expect(finished.tally.firstTryCorrect, 6);
      expect(h.api.answerBodies.map((b) => b['exerciseId']), [
        for (var q = 1; q <= 6; q++) 'u1-l1-q$q',
      ]);
      expect(h.api.requests.last.$1, '/v1/lessons/u1-l1/complete');
    });

    test('a wrong answer comes back once at the end', () async {
      final h = Harness('u1-l1');
      await h.start();

      await h.answer(correct: false);
      final checked = h.playing.status as Checked;
      expect(checked.response.correct, isFalse);
      expect(checked.correctAnswer, isA<CorrectText>());
      expect(
        (checked.correctAnswer as CorrectText).text,
        'それまでの文の続きとして、次に来そうなことばを予測する',
      );
      expect(h.playing.steps, hasLength(7));
      expect(h.playing.steps.last.isReview, isTrue);
      expect(h.playing.steps.last.exercise.id, 'u1-l1-q1');
      await h.controller.next();

      for (var i = 0; i < 5; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }
      expect(h.playing.step.isReview, isTrue);
      expect(h.playing.step.exercise.id, 'u1-l1-q1');
      expect(h.playing.draft.toAnswer(), isNull, reason: 'fresh draft');

      await h.answer(correct: false);
      expect(h.playing.steps, hasLength(7), reason: 'queued only once');
      await h.controller.next();

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonCompleted>());
      expect(finished.tally.firstTryCorrect, 5);
      expect(finished.xpGained, 5 * 10 + 20);
      expect(h.api.answerBodies, hasLength(7));
    });

    test(
      'the correct order and filled template are resolved to texts',
      () async {
        final h = Harness('u1-l1');
        await h.start();
        for (var i = 0; i < 3; i++) {
          await h.answer(correct: true);
          await h.controller.next();
        }
        await h.answer(correct: false);
        expect(
          ((h.playing.status as Checked).correctAnswer as CorrectSequence)
              .texts,
          [
            '人が質問や指示を入力する',
            '次に来そうなことばを予測して、1 つ選ぶ',
            '選んだことばを、文の最後につけたす',
            'これをくり返して、長い文章ができあがる',
          ],
        );
        await h.controller.next();
        await h.answer(correct: true);
        await h.controller.next();
        await h.answer(correct: false);
        expect(
          ((h.playing.status as Checked).correctAnswer as CorrectText).text,
          '生成 AI は、大量の文章データから、ことばのつながり方を学び、次に来ることばを予測している。',
        );
      },
    );

    test('skipped exercises are not sent and the 409 is shown as not '
        'completed', () async {
      const prompt = PromptExercise(
        id: 'u1-l1-q7',
        lessonId: 'u1-l1',
        question: 'プロンプトを書こう',
        task: '自由研究のテーマを AI に相談しよう',
        maxLength: 400,
      );
      final lesson = unit1.lessonJson('u1-l1');
      (lesson['exerciseIds']! as List).insert(1, 'u1-l1-q7');
      final content = unit1Content();
      content.lessons = [
        for (final l in content.lessons)
          if (l.id == 'u1-l1') Lesson.fromJson(lesson) else l,
      ];
      content.exercises['u1-l1-q7'] = prompt;
      final api = FakeLearningApi(
        answerKeys: unit1.answerKeys,
        lessonExercises: {
          'u1-l1': [...unit1.lesson('u1-l1').exerciseIds, 'u1-l1-q7'],
        },
      );
      final h = Harness('u1-l1', content: content, api: api);
      await h.start();

      await h.answer(correct: true);
      await h.controller.next();
      expect(h.playing.draft, isA<PromptDraft>());
      api.promptGradingOn =
          false; // AI grading off: the prompt cannot be graded
      h.controller.editPrompt('自由研究のテーマを 3 つ出して');
      await h.controller.evaluatePrompt();
      expect(h.playing.status, isA<SubmitFailed>());
      await h.controller.skipPrompt();
      for (var i = 0; i < 5; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonNotCompleted>());
      expect(finished.tally.skipped, 1);
      expect(finished.xpGained, 60);
      expect(finished.progress?.xp, 60, reason: 'from the last answer');
      expect(
        api.answerBodies.map((b) => b['exerciseId']),
        isNot(contains('u1-l1-q7')),
      );
    });

    test('only a prompt that could not be graded is skipped', () async {
      final h = Harness('u1-l1');
      await h.start();

      expect(h.controller.skipPrompt, throwsStateError);
    });
  });

  group('failures', () {
    test('a network error keeps the answer and the retry sends it', () async {
      final h = Harness('u1-l1');
      await h.start();
      h.api.failNext('/v1/answers', http.ClientException('offline'));

      await h.answer(correct: true);

      expect(h.playing.status, isA<SubmitFailed>());
      expect((h.playing.draft as ChoiceDraft).selectedOptionId, 'b');
      expect(h.playing.isEditable, isTrue);

      await h.controller.check();

      expect((h.playing.status as Checked).response.correct, isTrue);
      expect(h.api.answerBodies, hasLength(2));
      expect(h.api.answerBodies.first, h.api.answerBodies.last);
    });

    test('a 5xx while sending is a retryable failure too', () async {
      final h = Harness('u1-l1');
      await h.start();
      h.api.failNext(
        '/v1/answers',
        FakeLearningApi.errorResponse(503, 'upstream_unavailable'),
      );

      await h.answer(correct: true);

      expect(h.playing.status, isA<SubmitFailed>());
      await h.controller.check();
      expect(h.playing.status, isA<Checked>());
    });

    test('a failed completion can be sent again', () async {
      final h = Harness('u1-l1');
      await h.start();
      h.api.failNext(
        '/v1/lessons/u1-l1/complete',
        FakeLearningApi.errorResponse(500, 'internal'),
      );

      for (var i = 0; i < 6; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }

      final failed = h.state as LessonCompleteFailed;
      expect(failed.tally.xpGained, 60);

      await h.controller.retryCompletion();

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonCompleted>());
      expect(finished.xpGained, 80);
    });
  });

  group('hallucination', () {
    /// u1-l1 with the hallucination exercise first.
    Harness harness() {
      final lesson = hallucinationFixture.lessonU1L1(position: 0);
      return Harness(
        'u1-l1',
        content: FakeContentRepository(
          lessons: hallucinationFixture.unit1Lessons(position: 0),
          exercises: hallucinationFixture.unit1Exercises,
        ),
        api: FakeLearningApi(
          answerKeys: hallucinationFixture.answerKeys,
          lessonExercises: {lesson.id: lesson.exerciseIds},
        ),
        answerKeys: hallucinationFixture.answerKeys,
      );
    }

    List<SentenceVerdict> verdicts(Harness h) => [
      for (final s
          in ((h.playing.status as Checked).correctAnswer
                  as CorrectHallucination)
              .review
              .sentences)
        s.verdict,
    ];

    test('sentences toggle; check needs at least one', () async {
      final h = harness();
      await h.start();

      expect(h.playing.draft, isA<HallucinationDraft>());
      expect(h.playing.draft.toAnswer(), isNull);
      expect(h.controller.check, throwsStateError);
      h.controller
        ..toggleSentence(4)
        ..toggleSentence(0)
        ..toggleSentence(2)
        ..toggleSentence(0);
      expect((h.playing.draft as HallucinationDraft).selectedIndexes, {4, 2});
      expect(h.playing.draft.toAnswer()?.toJson(), {
        'type': 'hallucination',
        'sentenceIndexes': [2, 4],
      });
      h.controller
        ..toggleSentence(2)
        ..toggleSentence(4);
      expect(h.playing.draft.toAnswer(), isNull);
      expect(() => h.controller.toggleSentence(5), throwsArgumentError);
      expect(() => h.controller.toggleSentence(-1), throwsArgumentError);
      expect(() => h.controller.selectOption('a'), throwsStateError);
    });

    test('a correct answer is sent and resolved per sentence', () async {
      final h = harness();
      await h.start();

      await h.answer(correct: true);

      final checked = h.playing.status as Checked;
      expect(checked.response.correct, isTrue);
      expect(h.playing.steps, hasLength(7), reason: 'nothing queued');
      expect(h.api.answerBodies.single, {
        'exerciseId': HallucinationFixture.exerciseId,
        'answer': {
          'type': 'hallucination',
          'sentenceIndexes': [1, 4],
        },
      });
      expect(verdicts(h), [
        SentenceVerdict.untouched,
        SentenceVerdict.found,
        SentenceVerdict.untouched,
        SentenceVerdict.untouched,
        SentenceVerdict.found,
      ]);
      final review = (checked.correctAnswer as CorrectHallucination).review;
      expect(review.errors.map((s) => s.error!.errorType), [
        HallucinationErrorType.number,
        HallucinationErrorType.fakeSource,
      ]);
      h.controller.toggleSentence(0);
      expect((h.playing.draft as HallucinationDraft).selectedIndexes, {
        1,
        4,
      }, reason: 'no edits after checking');
    });

    test('a wrong answer comes back once at the end', () async {
      final h = harness();
      await h.start();

      await h.answer(correct: false);

      expect((h.playing.status as Checked).response.correct, isFalse);
      // The key lists sentence 4 first, so the harness misses it.
      expect(verdicts(h), [
        SentenceVerdict.falseAlarm,
        SentenceVerdict.found,
        SentenceVerdict.untouched,
        SentenceVerdict.untouched,
        SentenceVerdict.missed,
      ]);
      expect(h.playing.steps, hasLength(8));
      expect(h.playing.steps.last.isReview, isTrue);
      expect(h.playing.steps.last.exercise.id, HallucinationFixture.exerciseId);
      await h.controller.next();
      for (var i = 0; i < 6; i++) {
        await h.answer(correct: true);
        await h.controller.next();
      }

      expect(h.playing.step.isReview, isTrue);
      final draft = h.playing.draft as HallucinationDraft;
      expect(draft.selectedIndexes, isEmpty, reason: 'fresh draft');
      await h.answer(correct: true);
      expect(h.playing.steps, hasLength(8));
      await h.controller.next();

      final finished = h.state as LessonFinished;
      expect(finished.outcome, isA<LessonCompleted>());
      expect(finished.tally.firstTryCorrect, 6);
      expect(finished.xpGained, 7 * 10 + 20);
      expect(h.api.answerBodies, hasLength(8));
    });

    test('a result that does not fit the sentences is retryable', () async {
      final h = harness();
      await h.start();
      h.api.failNext(
        '/v1/answers',
        http.Response(
          jsonEncode({
            'attemptId': 'a1',
            'correct': true,
            'result': {
              'type': 'hallucination',
              'errors': <Object>[],
              'found': [9],
              'missed': <int>[],
              'falseAlarms': <int>[],
            },
            'progress': {'xp': 0, 'xpGained': 0, 'streakDays': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await h.answer(correct: true);

      expect((h.playing.status as SubmitFailed).error, isA<FormatException>());
      await h.controller.check();
      expect((h.playing.status as Checked).response.correct, isTrue);
    });
  });
}
