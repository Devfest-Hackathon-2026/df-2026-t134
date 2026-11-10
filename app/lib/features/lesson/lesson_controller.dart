import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../data/providers.dart';
import '../../models/answer.dart';
import '../../models/content.dart';
import '../../models/exercise.dart';
import '../../models/json_fields.dart';
import '../../models/live_check.dart';
import '../../models/prompt_evaluation.dart';
import 'hallucination_review.dart';
import 'lesson_state.dart';

/// The lesson being played at `/lessons/:lessonId`; the single source of
/// truth for the current step, the draft answer, sending and the review queue.
final lessonControllerProvider = AsyncNotifierProvider.autoDispose
    .family<LessonController, LessonState, String>(
      LessonController.new,
      retry: noRetry,
    );

class LessonController extends AsyncNotifier<LessonState> {
  LessonController(this.lessonId);

  final String lessonId;

  @override
  Future<LessonState> build() async {
    // The id comes from the URL, so check it before using it as a doc path.
    if (!isContractId(lessonId)) {
      return LessonNotFound(lessonId);
    }
    final content = ref.watch(contentRepositoryProvider);
    final lesson = await content.fetchLesson(lessonId);
    if (lesson == null) {
      return LessonNotFound(lessonId);
    }
    if (lesson.exerciseIds.toSet().length != lesson.exerciseIds.length) {
      throw FormatException('Lesson ${lesson.id} repeats an exercise');
    }
    final exercises = await content.fetchExercises(lesson.exerciseIds);
    for (final (i, exercise) in exercises.indexed) {
      if (exercise.id != lesson.exerciseIds[i] ||
          exercise.lessonId != lesson.id) {
        throw FormatException(
          'Exercise ${exercise.id} does not belong to lesson ${lesson.id}',
        );
      }
    }
    return LessonIntro(lesson, exercises);
  }

  /// Leaves the mascot intro and shows the first exercise.
  void start() {
    final current = state.requireValue;
    if (current is! LessonIntro) {
      throw StateError('start() outside the intro: $current');
    }
    state = AsyncData(LessonPlaying.start(current));
  }

  void selectOption(String optionId) =>
      _editDraft<ChoiceDraft>((draft) => draft.select(optionId));

  void addOrderItem(String itemId) =>
      _editDraft<OrderDraft>((draft) => draft.add(itemId));

  void removeOrderItem(String itemId) =>
      _editDraft<OrderDraft>((draft) => draft.remove(itemId));

  void undoOrderItem() => _editDraft<OrderDraft>((draft) => draft.undo());

  void chooseBlankOption(String blankId, String optionId) =>
      _editDraft<FillBlankDraft>((draft) => draft.choose(blankId, optionId));

  void toggleSentence(int index) =>
      _editDraft<HallucinationDraft>((draft) => draft.toggle(index));

  void editPrompt(String text) =>
      _editDraft<PromptDraft>((draft) => draft.edit(text));

  void editLiveCheckPrompt(String text) =>
      _editDraft<LiveCheckDraft>((draft) => draft.edit(text));

  void toggleLiveCheckSentence(int index) =>
      _editDraft<LiveCheckDraft>((draft) => draft.toggle(index));
  void skipStoryScenes() =>
      _editDraft<StoryDraft>((draft) => draft.skipScenes());

  void selectStoryOption(String optionId) =>
      _editDraft<StoryDraft>((draft) => draft.select(optionId));

  /// The next scene of a story: one of its scenes before the question, or
  /// of the chosen outcome after the check.
  void nextStoryScene() {
    final playing = _playing();
    final draft = playing.draft;
    if (draft is! StoryDraft) {
      throw StateError('The current exercise is not a story');
    }
    switch (playing.status) {
      case Checked(response: SubmitAnswerResponse(:final StoryResult result)):
        state = AsyncData(
          playing.withStoryDraft(draft.nextOutcomeScene(result)),
        );
      case Answering() || SubmitFailed():
        _editDraft<StoryDraft>((draft) => draft.nextScene());
      case Submitting() || Checked() || PromptChecked():
        return;
    }
  }

  /// Sends the draft to `/v1/answers`. Also the retry after [SubmitFailed]:
  /// the draft is kept on failure.
  Future<void> check() async {
    final playing = _playing();
    if (!playing.isEditable) {
      return; // already sending or checked
    }
    final answer = playing.draft.toAnswer();
    if (answer == null) {
      throw StateError('check() with an incomplete answer');
    }
    final exercise = playing.step.exercise;
    state = AsyncData(playing.withStatus(const Submitting()));
    try {
      final response = await ref
          .read(apiClientProvider)
          .submitAnswer(
            SubmitAnswerRequest(exerciseId: exercise.id, answer: answer),
          );
      final correctAnswer = switch (playing.draft) {
        final LiveCheckDraft draft => describeLiveCheck(draft, response.result),
        _ => describeCorrectAnswer(exercise, response.result),
      };
      if (ref.mounted) {
        state = AsyncData(playing.checked(response, correctAnswer));
      }
    } on Exception catch (error) {
      // Network, 5xx and malformed responses alike: the learner can retry.
      if (ref.mounted) {
        state = AsyncData(playing.withStatus(SubmitFailed(error)));
      }
    }
  }

  /// Moves on after the feedback; after the last step completes the lesson.
  Future<void> next() async {
    final playing = _playing();
    if (playing.status is! Checked && playing.status is! PromptChecked) {
      throw StateError('next() before the answer is checked');
    }
    if ((playing.draft, playing.status)
        case (
          final StoryDraft draft,
          Checked(response: SubmitAnswerResponse(:final StoryResult result)),
        )
        when !draft.outcomeDone(result)) {
      throw StateError('next() before the story outcome has played');
    }
    await _advance(playing, playing.tally);
  }

  /// Sends the prompt to `/v1/prompt/evaluate`; also the retry after
  /// [SubmitFailed]. The text is kept whatever happens: a `blocked` answer
  /// goes back to editing with the server's message in the draft, and errors
  /// (AI grading off, daily limit, network) become [SubmitFailed].
  Future<void> evaluatePrompt() async {
    final playing = _playing();
    if (!playing.isEditable) {
      return; // already sending or graded
    }
    final draft = playing.draft;
    if (draft is! PromptDraft) {
      throw StateError('evaluatePrompt() outside a prompt exercise');
    }
    final prompt = draft.promptToSend;
    if (prompt == null) {
      throw StateError('evaluatePrompt() with an empty or too long prompt');
    }
    final sending = playing
        .withDraft(draft.unblocked())
        .withStatus(const Submitting());
    state = AsyncData(sending);
    try {
      final response = await ref
          .read(apiClientProvider)
          .evaluatePrompt(exerciseId: draft.exercise.id, prompt: prompt);
      if (ref.mounted) {
        state = AsyncData(switch (response) {
          PromptEvaluated() => sending.promptChecked(response),
          PromptBlocked() => sending.withDraft(draft.block(response)),
        });
      }
    } on Exception catch (error) {
      if (ref.mounted) {
        state = AsyncData(sending.withStatus(SubmitFailed(error)));
      }
    }
  }

  /// Moves past a prompt exercise that could not be graded (e.g. AI grading
  /// is off). Nothing is recorded, so the lesson ends as not completed.
  Future<void> skipPrompt() async {
    final playing = _playing();
    if (playing.draft is! PromptDraft || playing.status is! SubmitFailed) {
      throw StateError('Only a prompt that could not be graded is skipped');
    }
    await _advance(playing, playing.tally.skip());
  }

  /// Sends the live check prompt to `/v1/live-checks`; also the retry after
  /// [SubmitFailed]. Like [evaluatePrompt], the text is kept whatever
  /// happens: `blocked` goes back to editing with the server's message, and
  /// errors (AI off, daily limit, network) become [SubmitFailed].
  Future<void> startLiveCheck() async {
    final playing = _playing();
    if (!playing.isEditable) {
      return; // already waiting for the AI
    }
    final draft = playing.draft;
    if (draft is! LiveCheckDraft) {
      throw StateError('startLiveCheck() outside a live check');
    }
    final prompt = draft.promptToSend;
    if (prompt == null) {
      throw StateError('startLiveCheck() without a prompt to send');
    }
    final sending = playing
        .withDraft(draft.unblocked())
        .withStatus(const Submitting());
    state = AsyncData(sending);
    try {
      final response = await ref
          .read(apiClientProvider)
          .startLiveCheck(exerciseId: draft.exercise.id, prompt: prompt);
      if (ref.mounted) {
        state = AsyncData(switch (response) {
          LiveCheckStarted() => sending.withDraft(
            draft.unblocked().started(response),
          ),
          LiveCheckBlocked() => sending.withDraft(draft.block(response)),
        });
      }
    } on Exception catch (error) {
      if (ref.mounted) {
        state = AsyncData(sending.withStatus(SubmitFailed(error)));
      }
    }
  }

  /// Fetches the sources of sentence [index] (one of the session's lookups)
  /// and returns them, or null when there are none to show (no lookups left,
  /// network errors; the draft then says why).
  Future<List<WebSource>?> lookUpSentence(int index) async {
    final playing = _playing();
    final draft = playing.draft;
    if (draft is! LiveCheckDraft || draft.session == null) {
      throw StateError('lookUpSentence() without a live check answer');
    }
    if (draft.lookups[index] case final sources?) {
      return sources; // looked up before: free
    }
    if (!playing.isEditable || !draft.canLookUp(index)) {
      return null;
    }
    final sessionId = draft.session!.sessionId;
    state = AsyncData(playing.withDraft(draft.lookingUpSentence(index)));
    try {
      final response = await ref
          .read(apiClientProvider)
          .lookupLiveCheck(sessionId: sessionId, sentenceIndex: index);
      _updateLiveCheck(sessionId, (d) => d.lookedUp(response));
      return response.sources;
    } on ApiException catch (error) {
      final failure = error.code == ApiErrorCode.conflict
          ? LookupFailure.noneLeft
          : LookupFailure.failed;
      _updateLiveCheck(sessionId, (d) => d.lookupFailed(index, failure));
    } on Exception {
      _updateLiveCheck(
        sessionId,
        (d) => d.lookupFailed(index, LookupFailure.failed),
      );
    }
    return null;
  }

  /// Moves past a live check that could not be started or answered (AI off,
  /// daily limit). Nothing is recorded, so the lesson ends as not completed.
  Future<void> skipLiveCheck() async {
    final playing = _playing();
    if (playing.draft is! LiveCheckDraft || playing.status is! SubmitFailed) {
      throw StateError('Only a live check that failed is skipped');
    }
    await _advance(playing, playing.tally.skip());
  }

  /// Applies [edit] to the live check draft of [sessionId] if it is still
  /// the current one (the learner may have moved on while waiting).
  void _updateLiveCheck(
    String sessionId,
    LiveCheckDraft Function(LiveCheckDraft draft) edit,
  ) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (current is! LessonPlaying) {
      return;
    }
    final draft = current.draft;
    if (draft is LiveCheckDraft && draft.session?.sessionId == sessionId) {
      // Keeps the status: a lookup never changes whether the step is sending.
      state = AsyncData(
        current.withDraft(edit(draft)).withStatus(current.status),
      );
    }
  }

  /// Sends `/complete` again after [LessonCompleteFailed].
  Future<void> retryCompletion() async {
    final current = state.requireValue;
    if (current is! LessonCompleteFailed) {
      throw StateError('retryCompletion() without a failed completion');
    }
    await _complete(current.lesson, current.questionCount, current.tally);
  }

  Future<void> _advance(LessonPlaying playing, LessonTally tally) async {
    final following = playing.advance(tally: tally);
    if (following != null) {
      state = AsyncData(following);
      return;
    }
    await _complete(playing.lesson, playing.questionCount, tally);
  }

  Future<void> _complete(
    Lesson lesson,
    int questionCount,
    LessonTally tally,
  ) async {
    state = AsyncData(LessonCompleting(lesson, questionCount, tally));
    LessonState next;
    try {
      final response = await ref
          .read(apiClientProvider)
          .completeLesson(lesson.id);
      next = LessonFinished(
        lesson,
        questionCount,
        tally,
        LessonCompleted(response.progress),
      );
    } on ApiException catch (error) {
      next = error.code == ApiErrorCode.conflict
          ? LessonFinished(
              lesson,
              questionCount,
              tally,
              const LessonNotCompleted(),
            )
          : LessonCompleteFailed(lesson, questionCount, tally, error);
    } on Exception catch (error) {
      // Network errors and malformed responses: the learner can retry.
      next = LessonCompleteFailed(lesson, questionCount, tally, error);
    }
    if (ref.mounted) {
      state = AsyncData(next);
    }
  }

  LessonPlaying _playing() {
    final current = state.requireValue;
    if (current is! LessonPlaying) {
      throw StateError('No exercise is being played: $current');
    }
    return current;
  }

  void _editDraft<D extends AnswerDraft>(AnswerDraft Function(D draft) edit) {
    final playing = _playing();
    if (!playing.isEditable) {
      return; // taps while sending or after checking change nothing
    }
    final draft = playing.draft;
    if (draft is! D) {
      throw StateError('The current exercise does not take a $D edit');
    }
    state = AsyncData(playing.withDraft(edit(draft)));
  }
}

/// Resolves a live check [result] against the session's sentences in
/// [draft]. Throws [FormatException] when it does not fit them.
CorrectAnswer describeLiveCheck(LiveCheckDraft draft, AnswerResult result) {
  if (result is! LiveCheckResult) {
    throw FormatException('Result ${result.type.wireName} is not a live check');
  }
  return CorrectLiveCheck(
    HallucinationReview.resolve(
      draft.asHallucination(),
      result.asHallucination,
    ),
    result.sources,
  );
}

/// Resolves the ids in [result] to the texts of [exercise]. Throws
/// [FormatException] when the server names ids the exercise does not have.
CorrectAnswer describeCorrectAnswer(Exercise exercise, AnswerResult result) {
  String textOf(List<Option> options, String id) {
    for (final option in options) {
      if (option.id == id) {
        return option.text;
      }
    }
    throw FormatException('Result names unknown id $id of ${exercise.id}');
  }

  switch ((exercise, result)) {
    case (ChoiceExercise(:final options), ChoiceResult(:final correctOptionId)):
      return CorrectText(textOf(options, correctOptionId));
    case (OrderExercise(:final items), OrderResult(:final correctOrder)):
      return CorrectSequence([
        for (final id in correctOrder) textOf(items, id),
      ]);
    case (
      FillBlankExercise(:final parts),
      FillBlankResult(:final correctOptions),
    ):
      final buffer = StringBuffer();
      for (final part in parts) {
        switch (part) {
          case TemplateText(:final text):
            buffer.write(text);
          case TemplateSlot(:final blank):
            final optionId = correctOptions[blank.id];
            if (optionId == null) {
              throw FormatException('Result misses blank ${blank.id}');
            }
            buffer.write(textOf(blank.options, optionId));
        }
      }
      return CorrectText(buffer.toString());
    case (final HallucinationExercise e, final HallucinationResult r):
      return CorrectHallucination(HallucinationReview.resolve(e, r));
    case (StoryExercise(:final options), StoryResult(:final bestOptionId)):
      return CorrectText(textOf(options, bestOptionId));
    default:
      throw FormatException(
        'Result ${result.type.wireName} does not fit ${exercise.type.wireName}',
      );
  }
}
