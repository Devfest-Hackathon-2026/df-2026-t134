import '../../models/answer.dart';
import '../../models/answer_mark.dart';
import '../../models/content.dart';
import '../../models/exercise.dart';
import '../../models/live_check.dart';
import '../../models/prompt_evaluation.dart';
import 'hallucination_review.dart';

/// The learner's answer to the current exercise while it is being built.
/// Holds its exercise so edits can be checked against the exercise's ids.
sealed class AnswerDraft {
  const AnswerDraft();

  /// An empty draft for [exercise].
  factory AnswerDraft.empty(Exercise exercise) => switch (exercise) {
    ChoiceExercise() => ChoiceDraft(exercise),
    OrderExercise() => OrderDraft(exercise),
    FillBlankExercise() => FillBlankDraft(exercise),
    HallucinationExercise() => HallucinationDraft(exercise),
    PromptExercise() => PromptDraft(exercise),
    LiveCheckExercise() => LiveCheckDraft(exercise),
    StoryExercise() => StoryDraft(exercise),
  };

  Exercise get exercise;

  /// The answer to submit, or null while it is incomplete.
  Answer? toAnswer();
}

final class ChoiceDraft extends AnswerDraft {
  const ChoiceDraft(this.exercise, {this.selectedOptionId});

  @override
  final ChoiceExercise exercise;
  final String? selectedOptionId;

  ChoiceDraft select(String optionId) {
    if (!exercise.options.any((o) => o.id == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'not in ${exercise.id}');
    }
    return ChoiceDraft(exercise, selectedOptionId: optionId);
  }

  @override
  Answer? toAnswer() => switch (selectedOptionId) {
    final id? => ChoiceAnswer(id),
    null => null,
  };
}

final class OrderDraft extends AnswerDraft {
  OrderDraft(this.exercise, {List<String> pickedIds = const []})
    : pickedIds = List.unmodifiable(pickedIds);

  @override
  final OrderExercise exercise;

  /// Item ids in the order the learner tapped them.
  final List<String> pickedIds;

  OrderDraft add(String itemId) {
    if (!exercise.items.any((i) => i.id == itemId)) {
      throw ArgumentError.value(itemId, 'itemId', 'not in ${exercise.id}');
    }
    if (pickedIds.contains(itemId)) {
      return this;
    }
    return OrderDraft(exercise, pickedIds: [...pickedIds, itemId]);
  }

  OrderDraft remove(String itemId) => OrderDraft(
    exercise,
    pickedIds: [
      for (final id in pickedIds)
        if (id != itemId) id,
    ],
  );

  /// Takes back the last placed item.
  OrderDraft undo() => pickedIds.isEmpty
      ? this
      : OrderDraft(
          exercise,
          pickedIds: pickedIds.sublist(0, pickedIds.length - 1),
        );

  @override
  Answer? toAnswer() =>
      pickedIds.length == exercise.items.length ? OrderAnswer(pickedIds) : null;
}

final class FillBlankDraft extends AnswerDraft {
  FillBlankDraft(this.exercise, {Map<String, String> selected = const {}})
    : selected = Map.unmodifiable(selected);

  @override
  final FillBlankExercise exercise;

  /// Blank id → option id, for the blanks filled so far.
  final Map<String, String> selected;

  FillBlankDraft choose(String blankId, String optionId) {
    final blank = exercise.blanks.where((b) => b.id == blankId).firstOrNull;
    if (blank == null || !blank.options.any((o) => o.id == optionId)) {
      throw ArgumentError('$blankId/$optionId is not in ${exercise.id}');
    }
    return FillBlankDraft(exercise, selected: {...selected, blankId: optionId});
  }

  @override
  Answer? toAnswer() => selected.length == exercise.blanks.length
      ? FillBlankAnswer(selected)
      : null;
}

final class HallucinationDraft extends AnswerDraft {
  HallucinationDraft(
    this.exercise, {
    Set<int> selectedIndexes = const {},
    List<AnswerMark> marks = const [],
    this.confirmedNoErrors = false,
  }) : selectedIndexes = Set.unmodifiable(selectedIndexes),
       marks = List.unmodifiable(marks);

  @override
  final HallucinationExercise exercise;

  /// Sentences the learner marked as wrong.
  final Set<int> selectedIndexes;

  final List<AnswerMark> marks;
  final bool confirmedNoErrors;
  List<AnswerMark> get selectionMarks => marks.isNotEmpty
      ? marks
      : [for (final i in selectedIndexes) sentenceMark(exercise.sentences, i)];
  HallucinationDraft withMarks(List<AnswerMark> values) => HallucinationDraft(
    exercise,
    selectedIndexes: markedIndexes(exercise.sentences, values),
    marks: values,
  );
  HallucinationDraft confirmNoErrors() =>
      HallucinationDraft(exercise, confirmedNoErrors: true);

  /// Marks the sentence at [index] as wrong, or unmarks it.
  HallucinationDraft toggle(int index) {
    if (index < 0 || index >= exercise.sentences.length) {
      throw ArgumentError.value(index, 'index', 'not in ${exercise.id}');
    }
    return HallucinationDraft(
      exercise,
      selectedIndexes: selectedIndexes.contains(index)
          ? selectedIndexes.difference({index})
          : {...selectedIndexes, index},
    );
  }

  /// An empty answer is sent only after the learner explicitly confirms it.
  @override
  Answer? toAnswer() => selectedIndexes.isEmpty && !confirmedNoErrors
      ? null
      : HallucinationAnswer(selectedIndexes.toList()..sort());
}

/// Q4: the prompt being written. It is graded by `/v1/prompt/evaluate`, not
/// sent as an [Answer].
final class PromptDraft extends AnswerDraft {
  const PromptDraft(this.exercise, {this.text = '', this.blocked});

  @override
  final PromptExercise exercise;

  /// What the learner typed, untrimmed.
  final String text;

  /// The server's last "blocked" answer, shown while the learner edits until
  /// the prompt is sent again.
  final PromptBlocked? blocked;

  /// Characters as the API counts them.
  int get length => promptLength(text);

  bool get isTooLong => length > exercise.maxLength;

  /// The trimmed prompt to send, or null while it is empty or too long.
  String? get promptToSend {
    final trimmed = text.trim();
    return trimmed.isEmpty || isTooLong ? null : trimmed;
  }

  PromptDraft edit(String text) =>
      PromptDraft(exercise, text: text, blocked: blocked);

  PromptDraft block(PromptBlocked blocked) =>
      PromptDraft(exercise, text: text, blocked: blocked);

  PromptDraft unblocked() => PromptDraft(exercise, text: text);

  @override
  Answer? toAnswer() => null;
}

/// Why a lookup gave no sources, shown at its sentence.
enum LookupFailure {
  /// 409 conflict: the server has no lookups left for the session.
  noneLeft,

  /// Network errors, 5xx and malformed responses: the learner may try again.
  failed,
}

/// Q10, in two phases. Composing ([session] is null): the learner writes a
/// prompt and sends it with `startLiveCheck` (the step is [Submitting] while
/// the AI answers). Investigating: the learner looks up sources and marks
/// the sentences they think are wrong; `check` sends the answer.
final class LiveCheckDraft extends AnswerDraft {
  LiveCheckDraft(
    this.exercise, {
    this.text = '',
    this.blocked,
    this.session,
    Set<int> selectedIndexes = const {},
    List<AnswerMark> marks = const [],
    this.confirmedNoErrors = false,
    Map<int, List<WebSource>> lookups = const {},
    this.lookupsLeft = 0,
    this.lookingUp,
    this.lookupFailure,
  }) : selectedIndexes = Set.unmodifiable(selectedIndexes),
       marks = List.unmodifiable(marks),
       lookups = Map.unmodifiable(lookups);

  @override
  final LiveCheckExercise exercise;

  /// The prompt as typed, untrimmed (kept after the answer arrives).
  final String text;

  /// The server's last "blocked" answer, shown while the learner edits.
  final LiveCheckBlocked? blocked;

  /// The AI's answer, once it arrived.
  final LiveCheckStarted? session;

  /// Sentences the learner marked as wrong.
  final Set<int> selectedIndexes;

  final List<AnswerMark> marks;
  final bool confirmedNoErrors;
  List<AnswerMark> get selectionMarks => marks.isNotEmpty
      ? marks
      : [for (final i in selectedIndexes) sentenceMark(session!.sentences, i)];
  LiveCheckDraft withMarks(List<AnswerMark> values) {
    _requirePhase(composing: false);
    return _copy(
      selectedIndexes: markedIndexes(session!.sentences, values),
      marks: values,
      confirmedNoErrors: false,
    );
  }

  LiveCheckDraft confirmNoErrors() {
    _requirePhase(composing: false);
    return _copy(selectedIndexes: {}, marks: [], confirmedNoErrors: true);
  }

  /// Sources of the sentences looked up so far (an empty list: none found).
  final Map<int, List<WebSource>> lookups;
  final int lookupsLeft;

  /// The sentence whose sources are being fetched.
  final int? lookingUp;
  final ({int index, LookupFailure failure})? lookupFailure;

  bool get isComposing => session == null;

  /// Characters as the API counts them.
  int get length => promptLength(text);

  bool get isTooLong => length > exercise.maxLength;

  /// The trimmed prompt to send, or null while it is empty, too long or the
  /// answer already arrived.
  String? get promptToSend {
    final trimmed = text.trim();
    return !isComposing || trimmed.isEmpty || isTooLong ? null : trimmed;
  }

  /// Whether [index] can be looked up now (a sentence already looked up is
  /// shown again without asking the server).
  bool canLookUp(int index) =>
      session != null &&
      lookingUp == null &&
      lookupsLeft > 0 &&
      !lookups.containsKey(index);

  LiveCheckDraft edit(String text) {
    _requirePhase(composing: true);
    return _copy(text: text);
  }

  LiveCheckDraft block(LiveCheckBlocked blocked) {
    _requirePhase(composing: true);
    return _copy(blocked: () => blocked);
  }

  LiveCheckDraft unblocked() => _copy(blocked: () => null);

  LiveCheckDraft started(LiveCheckStarted session) {
    _requirePhase(composing: true);
    if (session.sentences.length <= session.errorCount) {
      throw FormatException('Live check answer is too short', session);
    }
    return _copy(
      blocked: () => null,
      session: session,
      lookupsLeft: session.lookupsLeft,
    );
  }

  /// Marks the sentence at [index] as wrong, or unmarks it.
  LiveCheckDraft toggle(int index) {
    _checkIndex(index);
    return _copy(
      confirmedNoErrors: false,
      marks: [],
      selectedIndexes: selectedIndexes.contains(index)
          ? selectedIndexes.difference({index})
          : {...selectedIndexes, index},
    );
  }

  LiveCheckDraft lookingUpSentence(int index) {
    _checkIndex(index);
    if (!canLookUp(index)) {
      throw StateError('Sentence $index cannot be looked up now');
    }
    return _copy(lookingUp: () => index, lookupFailure: () => null);
  }

  LiveCheckDraft lookedUp(LookupResponse response) {
    _checkIndex(response.sentenceIndex);
    return _copy(
      lookups: {...lookups, response.sentenceIndex: response.sources},
      lookupsLeft: response.lookupsLeft,
      lookingUp: () => null,
    );
  }

  LiveCheckDraft lookupFailed(int index, LookupFailure failure) => _copy(
    lookupsLeft: failure == LookupFailure.noneLeft ? 0 : lookupsLeft,
    lookingUp: () => null,
    lookupFailure: () => (index: index, failure: failure),
  );

  /// Null until the learner marks content or explicitly chooses no errors.
  @override
  Answer? toAnswer() => switch (session) {
    final session? when selectedIndexes.isNotEmpty || confirmedNoErrors =>
      LiveCheckAnswer(
        sessionId: session.sessionId,
        sentenceIndexes: selectedIndexes.toList()..sort(),
      ),
    _ => null,
  };

  /// The answer as a hallucination exercise, so the checked sentences can be
  /// shown and reviewed like Q2.
  HallucinationExercise asHallucination() {
    final session = this.session;
    if (session == null) {
      throw StateError('No answer to review yet');
    }
    return HallucinationExercise(
      id: exercise.id,
      lessonId: exercise.lessonId,
      question: exercise.question,
      topic: exercise.theme,
      sentences: session.sentences,
      errorCount: session.errorCount,
    );
  }

  void _requirePhase({required bool composing}) {
    if (isComposing != composing) {
      throw StateError(
        'Not possible while ${isComposing ? '' : 'not '}composing',
      );
    }
  }

  void _checkIndex(int index) {
    final count = session?.sentences.length ?? 0;
    if (index < 0 || index >= count) {
      throw ArgumentError.value(index, 'index', 'not a sentence of the answer');
    }
  }

  // Nullable fields are passed as functions so that null can be set.
  LiveCheckDraft _copy({
    String? text,
    LiveCheckBlocked? Function()? blocked,
    LiveCheckStarted? session,
    Set<int>? selectedIndexes,
    List<AnswerMark>? marks,
    bool? confirmedNoErrors,
    Map<int, List<WebSource>>? lookups,
    int? lookupsLeft,
    int? Function()? lookingUp,
    ({int index, LookupFailure failure})? Function()? lookupFailure,
  }) => LiveCheckDraft(
    exercise,
    text: text ?? this.text,
    blocked: blocked == null ? this.blocked : blocked(),
    session: session ?? this.session,
    selectedIndexes: selectedIndexes ?? this.selectedIndexes,
    marks: marks ?? this.marks,
    confirmedNoErrors: confirmedNoErrors ?? this.confirmedNoErrors,
    lookups: lookups ?? this.lookups,
    lookupsLeft: lookupsLeft ?? this.lookupsLeft,
    lookingUp: lookingUp == null ? this.lookingUp : lookingUp(),
    lookupFailure: lookupFailure == null ? this.lookupFailure : lookupFailure(),
  );
}

/// One exercise in the play order. Wrong answers add a review step for the
/// same exercise at the end of the lesson (once per exercise).
class LessonStep {
  const LessonStep.first(this.exercise) : isReview = false;

  const LessonStep.review(this.exercise) : isReview = true;

  final Exercise exercise;
  final bool isReview;
}

/// The correct answer from the server, resolved to the exercise's texts.
sealed class CorrectAnswer {
  const CorrectAnswer();
}

final class CorrectText extends CorrectAnswer {
  const CorrectText(this.text);

  final String text;
}

final class CorrectSequence extends CorrectAnswer {
  CorrectSequence(List<String> texts) : texts = List.unmodifiable(texts);

  final List<String> texts;
}

/// The hallucination result resolved to the exercise's sentences.
final class CorrectHallucination extends CorrectAnswer {
  const CorrectHallucination(this.review);

  final HallucinationReview review;
}

/// The live check result resolved to the session's sentences, with every
/// source of the correct answer.
final class CorrectLiveCheck extends CorrectAnswer {
  CorrectLiveCheck(this.review, List<WebSource> sources)
    : sources = List.unmodifiable(sources);

  final HallucinationReview review;
  final List<WebSource> sources;
}

/// Where the current step is between answering and moving on.
sealed class StepStatus {
  const StepStatus();
}

final class Answering extends StepStatus {
  const Answering();
}

final class Submitting extends StepStatus {
  const Submitting();
}

/// Sending failed; the draft is kept so the learner can send it again.
final class SubmitFailed extends StepStatus {
  const SubmitFailed(this.error);

  final Object error;
}

final class Checked extends StepStatus {
  const Checked(this.response, this.correctAnswer);

  final SubmitAnswerResponse response;
  final CorrectAnswer correctAnswer;
}

/// Q4: the prompt was graded. Prompt exercises are not queued for review.
final class PromptChecked extends StepStatus {
  const PromptChecked(this.evaluation);

  final PromptEvaluated evaluation;
}

/// What the learner has done so far, for the result screen.
class LessonTally {
  const LessonTally({
    this.xpGained = 0,
    this.lastProgress,
    this.firstTryCorrect = 0,
    this.skipped = 0,
  });

  /// XP from answers (the completion bonus is added on the result screen).
  final int xpGained;

  /// Progress returned by the last answer, if any was sent.
  final ProgressSnapshot? lastProgress;

  /// Exercises answered correctly on their first step.
  final int firstTryCorrect;
  final int skipped;

  LessonTally record(SubmitAnswerResponse response, LessonStep step) =>
      LessonTally(
        xpGained: xpGained + response.progress.xpGained,
        lastProgress: response.progress,
        firstTryCorrect:
            firstTryCorrect + (response.correct && !step.isReview ? 1 : 0),
        skipped: skipped,
      );

  /// A graded prompt; a passing total counts like a correct answer.
  LessonTally recordPrompt(PromptEvaluated evaluation) => LessonTally(
    xpGained: xpGained + evaluation.progress.xpGained,
    lastProgress: evaluation.progress,
    firstTryCorrect: firstTryCorrect + (evaluation.passed ? 1 : 0),
    skipped: skipped,
  );

  LessonTally skip() => LessonTally(
    xpGained: xpGained,
    lastProgress: lastProgress,
    firstTryCorrect: firstTryCorrect,
    skipped: skipped + 1,
  );
}

/// State of the lesson screen. The [LessonController] is its only writer.
sealed class LessonState {
  const LessonState();
}

final class LessonNotFound extends LessonState {
  const LessonNotFound(this.lessonId);

  final String lessonId;
}

/// The mascot introduces the lesson; nothing has been answered yet.
final class LessonIntro extends LessonState {
  LessonIntro(this.lesson, List<Exercise> exercises)
    : exercises = List.unmodifiable(exercises);

  final Lesson lesson;

  /// In `lesson.exerciseIds` order.
  final List<Exercise> exercises;
}

final class LessonPlaying extends LessonState {
  LessonPlaying({
    required this.lesson,
    required this.questionCount,
    required List<LessonStep> steps,
    required this.index,
    required this.draft,
    required this.status,
    required this.tally,
  }) : steps = List.unmodifiable(steps) {
    if (index < 0 || index >= this.steps.length) {
      throw RangeError.index(index, this.steps, 'index');
    }
  }

  /// The first step of [intro].
  factory LessonPlaying.start(LessonIntro intro) {
    final steps = [for (final e in intro.exercises) LessonStep.first(e)];
    return LessonPlaying(
      lesson: intro.lesson,
      questionCount: steps.length,
      steps: steps,
      index: 0,
      draft: AnswerDraft.empty(steps.first.exercise),
      status: const Answering(),
      tally: const LessonTally(),
    );
  }

  final Lesson lesson;

  /// Exercises in the lesson (review steps not counted).
  final int questionCount;

  /// Play order; review steps are appended after wrong answers.
  final List<LessonStep> steps;
  final int index;
  final AnswerDraft draft;
  final StepStatus status;
  final LessonTally tally;

  LessonStep get step => steps[index];

  /// The draft can change and be sent.
  bool get isEditable => status is Answering || status is SubmitFailed;

  /// Share of steps done, counting the current one once it is checked.
  double get progress =>
      (index + (status is Checked || status is PromptChecked ? 1 : 0)) /
      steps.length.toDouble();

  LessonPlaying withDraft(AnswerDraft draft) =>
      _copy(draft: draft, status: const Answering());

  LessonPlaying withStatus(StepStatus status) => _copy(status: status);

  /// Moves through a story's scenes without touching the status: the
  /// outcome scenes play while the answer stays checked.
  LessonPlaying withStoryDraft(StoryDraft draft) => _copy(draft: draft);

  /// Records [response] and, for a first wrong answer, queues a review step.
  LessonPlaying checked(
    SubmitAnswerResponse response,
    CorrectAnswer correctAnswer,
  ) => _copy(
    steps: !response.correct && !step.isReview
        ? [...steps, LessonStep.review(step.exercise)]
        : steps,
    status: Checked(response, correctAnswer),
    tally: tally.record(response, step),
  );

  /// Records a graded prompt (never queues a review step).
  LessonPlaying promptChecked(PromptEvaluated evaluation) => _copy(
    status: PromptChecked(evaluation),
    tally: tally.recordPrompt(evaluation),
  );

  /// The next step, or null when this was the last one.
  LessonPlaying? advance({required LessonTally tally}) {
    final next = index + 1;
    if (next >= steps.length) {
      return null;
    }
    return _copy(
      index: next,
      draft: AnswerDraft.empty(steps[next].exercise),
      status: const Answering(),
      tally: tally,
    );
  }

  LessonPlaying _copy({
    List<LessonStep>? steps,
    int? index,
    AnswerDraft? draft,
    StepStatus? status,
    LessonTally? tally,
  }) => LessonPlaying(
    lesson: lesson,
    questionCount: questionCount,
    steps: steps ?? this.steps,
    index: index ?? this.index,
    draft: draft ?? this.draft,
    status: status ?? this.status,
    tally: tally ?? this.tally,
  );
}

/// Every step is done; `/complete` is being sent.
final class LessonCompleting extends LessonState {
  const LessonCompleting(this.lesson, this.questionCount, this.tally);

  final Lesson lesson;
  final int questionCount;
  final LessonTally tally;
}

/// `/complete` failed for a temporary reason; it can be sent again.
final class LessonCompleteFailed extends LessonState {
  const LessonCompleteFailed(
    this.lesson,
    this.questionCount,
    this.tally,
    this.error,
  );

  final Lesson lesson;
  final int questionCount;
  final LessonTally tally;
  final Object error;
}

/// How `/complete` ended.
sealed class LessonOutcome {
  const LessonOutcome();
}

/// The server counted the lesson (bonus XP and streak in [progress]).
final class LessonCompleted extends LessonOutcome {
  const LessonCompleted(this.progress);

  final ProgressSnapshot progress;
}

/// 409 conflict: some exercise has no attempt yet (e.g. it was skipped), so
/// there is no completion bonus.
final class LessonNotCompleted extends LessonOutcome {
  const LessonNotCompleted();
}

final class LessonFinished extends LessonState {
  const LessonFinished(
    this.lesson,
    this.questionCount,
    this.tally,
    this.outcome,
  );

  final Lesson lesson;
  final int questionCount;
  final LessonTally tally;
  final LessonOutcome outcome;

  /// Answers plus the completion bonus.
  int get xpGained => switch (outcome) {
    LessonCompleted(:final progress) => tally.xpGained + progress.xpGained,
    LessonNotCompleted() => tally.xpGained,
  };

  /// The latest progress known from the server, if any.
  ProgressSnapshot? get progress => switch (outcome) {
    LessonCompleted(:final progress) => progress,
    LessonNotCompleted() => tally.lastProgress,
  };
}

final class StoryDraft extends AnswerDraft {
  const StoryDraft(
    this.exercise, {
    this.sceneIndex = 0,
    this.selectedOptionId,
    this.outcomeIndex = 0,
  });

  @override
  final StoryExercise exercise;

  /// The scene on screen; `scenes.length` once every scene has been shown
  /// and the question is asked.
  final int sceneIndex;
  final String? selectedOptionId;

  /// The outcome scene on screen after the check; the outcome's length once
  /// it has played.
  final int outcomeIndex;

  bool get isDeciding => sceneIndex >= exercise.scenes.length;

  StoryDraft nextScene() {
    if (isDeciding) {
      throw StateError('Every scene of ${exercise.id} has been shown');
    }
    return _copy(sceneIndex: sceneIndex + 1);
  }

  /// Jumps to the question (e.g. on a review step).
  StoryDraft skipScenes() => _copy(sceneIndex: exercise.scenes.length);

  StoryDraft select(String optionId) {
    if (!isDeciding) {
      throw StateError('Options of ${exercise.id} are shown after the scenes');
    }
    if (!exercise.options.any((o) => o.id == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'not in ${exercise.id}');
    }
    return _copy(selectedOptionId: optionId);
  }

  /// Whether [result]'s outcome has played to the end.
  bool outcomeDone(StoryResult result) => outcomeIndex >= result.outcome.length;

  StoryDraft nextOutcomeScene(StoryResult result) {
    if (outcomeDone(result)) {
      throw StateError('The outcome of ${exercise.id} has been shown');
    }
    return _copy(outcomeIndex: outcomeIndex + 1);
  }

  @override
  Answer? toAnswer() => switch (selectedOptionId) {
    final id? when isDeciding => StoryAnswer(id),
    _ => null,
  };

  StoryDraft _copy({
    int? sceneIndex,
    String? selectedOptionId,
    int? outcomeIndex,
  }) => StoryDraft(
    exercise,
    sceneIndex: sceneIndex ?? this.sceneIndex,
    selectedOptionId: selectedOptionId ?? this.selectedOptionId,
    outcomeIndex: outcomeIndex ?? this.outcomeIndex,
  );
}
