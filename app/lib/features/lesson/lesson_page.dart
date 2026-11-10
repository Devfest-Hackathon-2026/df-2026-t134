import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../design/chapter_theme.dart';
import '../../design/motion.dart';
import '../../models/answer.dart';
import 'lesson_controller.dart';
import 'lesson_state.dart';
import 'widgets/answer_feedback_panel.dart';
import 'widgets/choice_exercise_view.dart';
import 'widgets/fill_blank_exercise_view.dart';
import 'widgets/hallucination_exercise_view.dart';
import 'widgets/lesson_result_view.dart';
import 'widgets/live_check_action_bar.dart';
import 'widgets/live_check_exercise_view.dart';
import 'widgets/mascot_bubble.dart';
import 'widgets/order_exercise_view.dart';
import 'widgets/prompt_exercise_view.dart';
import 'widgets/prompt_feedback_view.dart';
import 'widgets/prompt_send_bar.dart';
import 'widgets/story_action_bar.dart';
import 'widgets/story_exercise_view.dart';

/// `/lessons/:lessonId`: intro → one exercise at a time → result.
/// Everything shown comes from [lessonControllerProvider].
class LessonPage extends ConsumerWidget {
  const LessonPage({super.key, required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lessonControllerProvider(lessonId);
    final controller = ref.read(provider.notifier);
    final lessonState = ref.watch(provider);
    final lesson = switch (lessonState) {
      AsyncData(value: LessonIntro(:final lesson)) ||
      AsyncData(value: LessonPlaying(:final lesson)) ||
      AsyncData(value: LessonCompleting(:final lesson)) ||
      AsyncData(value: LessonCompleteFailed(:final lesson)) ||
      AsyncData(value: LessonFinished(:final lesson)) => lesson,
      _ => null,
    };
    final palette = lesson == null
        ? ChapterPalette.common
        : ChapterPalette.forUnit(lesson.unitId);
    final body = switch (lessonState) {
      AsyncData(value: final state) => switch (state) {
        LessonNotFound() => _MessageView(
          key: const Key('lesson-not-found'),
          icon: Icons.search_off_rounded,
          title: 'レッスンが見つかりませんでした',
          action: FilledButton(
            onPressed: () => _leave(context),
            child: const Text('学習パスにもどる'),
          ),
        ),
        LessonIntro() => _IntroView(intro: state, onStart: controller.start),
        LessonPlaying() => _PlayingView(playing: state, controller: controller),
        LessonCompleting() => const _MessageView(
          key: Key('lesson-completing'),
          icon: Icons.hourglass_top_rounded,
          title: 'けっかをまとめています…',
          action: CircularProgressIndicator(),
        ),
        LessonCompleteFailed() => _MessageView(
          key: const Key('lesson-complete-failed'),
          icon: Icons.cloud_off_rounded,
          title: 'けっかを送れませんでした',
          detail: '通信を確認して、もう一度送ってね。答えは消えていないよ',
          action: FilledButton(
            key: const Key('lesson-complete-retry'),
            onPressed: controller.retryCompletion,
            child: const Text('もう一度送る'),
          ),
        ),
        LessonFinished() => LessonResultView(
          finished: state,
          onBackToPath: () => _leave(context),
        ),
      },
      AsyncError() => _MessageView(
        key: const Key('lesson-load-error'),
        icon: Icons.cloud_off_rounded,
        title: 'レッスンを読みこめませんでした',
        detail: '通信を確認して、もう一度試してね',
        action: FilledButton(
          onPressed: () => ref.invalidate(provider),
          child: const Text('もう一度試す'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return ChapterScope(
      palette: palette,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('lesson-close'),
              tooltip: 'レッスンをやめる',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _leave(context),
            ),
            title: Text(
              palette.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            actions: [
              AmbientMotif(palette: palette, size: 44),
              const MotionSettingsButton(),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _leave(BuildContext context) =>
      context.canPop() ? context.pop() : context.go(Routes.path);
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.intro, required this.onStart});

  final LessonIntro intro;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final speech = intro.lesson.intro;
    return ListView(
      key: const Key('lesson-intro'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        Icon(
          Icons.auto_awesome_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          intro.lesson.title,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'ぜんぶで ${intro.exercises.length} もん',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        if (speech != null) ...[
          MascotBubble(speech: speech),
          const SizedBox(height: 32),
        ],
        Center(
          child: FilledButton(
            key: const Key('lesson-start'),
            onPressed: onStart,
            child: const Text('はじめる'),
          ),
        ),
      ],
    );
  }
}

class _PlayingView extends ConsumerWidget {
  const _PlayingView({required this.playing, required this.controller});

  final LessonPlaying playing;
  final LessonController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = playing.step;
    final exercise = step.exercise;
    final speech = exercise.intro;
    final status = playing.status;
    return LayoutBuilder(
      builder: (context, bounds) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressHeader(playing: playing),
          Expanded(
            child: TweenAnimationBuilder<double>(
              key: ValueKey('${exercise.id}-${step.isReview}'),
              tween: Tween(begin: reduceMotion(context, ref) ? 0 : 24, end: 0),
              duration: reduceMotion(context, ref)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) =>
                  Transform.translate(offset: Offset(offset, 0), child: child),
              child: ListView(
                key: Key('exercise-${exercise.id}'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  if (step.isReview)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        key: Key('review-badge'),
                        avatar: Icon(Icons.replay_rounded),
                        label: Text('ふくしゅう'),
                      ),
                    ),
                  if (speech != null) ...[
                    MascotBubble(speech: speech),
                    const SizedBox(height: 16),
                  ],
                  // A story asks its question after the scenes.
                  if (playing.draft is! StoryDraft) ...[
                    Text(
                      exercise.question,
                      key: const Key('exercise-question'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _exerciseView(),
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxHeight * .55),
            child: SingleChildScrollView(
              key: const Key('lesson-action-scroll'),
              child: switch (status) {
                Checked() when isStoryOutcomePlaying(playing) =>
                  _storyActionBar(),
                Checked() => AnswerFeedbackPanel(
                  checked: status,
                  step: step,
                  onNext: controller.next,
                ),
                PromptChecked(:final evaluation) => PromptFeedbackView(
                  evaluation: evaluation,
                  onNext: controller.next,
                ),
                _ when playing.draft is PromptDraft => PromptSendBar(
                  draft: playing.draft as PromptDraft,
                  status: status,
                  onSend: controller.evaluatePrompt,
                  onSkip: controller.skipPrompt,
                ),
                _ when playing.draft is LiveCheckDraft => LiveCheckActionBar(
                  draft: playing.draft as LiveCheckDraft,
                  status: status,
                  onStart: controller.startLiveCheck,
                  onCheck: controller.check,
                  onSkip: controller.skipLiveCheck,
                ),
                _ when playing.draft is StoryDraft => _storyActionBar(),
                _ => _CheckBar(playing: playing, onCheck: controller.check),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _storyActionBar() => StoryActionBar(
    playing: playing,
    onNextScene: controller.nextStoryScene,
    onSkipScenes: controller.skipStoryScenes,
    onChoose: controller.check,
  );

  Widget _exerciseView() {
    final editable = playing.isEditable;
    final result = switch (playing.status) {
      Checked(:final response) => response.result,
      _ => null,
    };
    return switch (playing.draft) {
      ChoiceDraft(:final exercise, :final selectedOptionId) =>
        ChoiceExerciseView(
          exercise: exercise,
          selectedOptionId: selectedOptionId,
          result: result as ChoiceResult?,
          onSelect: editable ? controller.selectOption : null,
        ),
      OrderDraft(:final exercise, :final pickedIds) => OrderExerciseView(
        exercise: exercise,
        pickedIds: pickedIds,
        result: result as OrderResult?,
        onAdd: editable ? controller.addOrderItem : null,
        onRemove: editable ? controller.removeOrderItem : null,
        onUndo: editable ? controller.undoOrderItem : null,
      ),
      FillBlankDraft(:final exercise, :final selected) => FillBlankExerciseView(
        exercise: exercise,
        selected: selected,
        result: result as FillBlankResult?,
        onChoose: editable ? controller.chooseBlankOption : null,
      ),
      HallucinationDraft(:final exercise, :final selectedIndexes) =>
        HallucinationExerciseView(
          exercise: exercise,
          selectedIndexes: selectedIndexes,
          review: switch (playing.status) {
            Checked(correctAnswer: CorrectHallucination(:final review)) =>
              review,
            _ => null,
          },
          onToggle: editable ? controller.toggleSentence : null,
        ),
      final PromptDraft draft => PromptExerciseView(
        draft: draft,
        onChanged: editable ? controller.editPrompt : null,
      ),
      final LiveCheckDraft draft => LiveCheckExerciseView(
        draft: draft,
        status: playing.status,
        review: switch (playing.status) {
          Checked(correctAnswer: CorrectLiveCheck(:final review)) => review,
          _ => null,
        },
        onChanged: editable ? controller.editLiveCheckPrompt : null,
        onToggle: editable ? controller.toggleLiveCheckSentence : null,
        onLookup: editable ? controller.lookUpSentence : null,
      final StoryDraft draft => StoryExerciseView(
        draft: draft,
        result: result as StoryResult?,
        onAdvance:
            (editable && !draft.isDeciding) || isStoryOutcomePlaying(playing)
            ? controller.nextStoryScene
            : null,
        onSelect: editable ? controller.selectStoryOption : null,
      ),
    };
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.playing});

  final LessonPlaying playing;

  @override
  Widget build(BuildContext context) {
    final done = (playing.progress * playing.steps.length).round();
    final label = '$done / ${playing.steps.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'しんちょく $label',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  key: const Key('lesson-progress'),
                  value: playing.progress,
                  minHeight: 8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 「チェック」, plus the error and retry when sending failed.
class _CheckBar extends StatelessWidget {
  const _CheckBar({required this.playing, required this.onCheck});

  final LessonPlaying playing;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = playing.status;
    final ready = playing.draft.toAnswer() != null;
    final hint = switch (playing.draft) {
      OrderDraft() => 'ぜんぶのカードをならべたらチェックしよう',
      FillBlankDraft() => 'ぜんぶの空らんをうめたらチェックしよう',
      HallucinationDraft() => 'まちがっていると思う文をタップしてからチェックしよう',
      ChoiceDraft() => '答えを 1 つえらんでね',
      PromptDraft() => 'プロンプトを書いたら送ろう',
      LiveCheckDraft() => 'まちがいだと思う文をタップしてから決定しよう',
      StoryDraft() => 'いちばんいいと思うものを 1 つえらんでね',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status is SubmitFailed) ...[
            Row(
              key: const Key('lesson-submit-error'),
              children: [
                Icon(Icons.wifi_off_rounded, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '送信できませんでした。答えはそのままだよ。もう一度送ってね',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (!ready) ...[
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            key: const Key('lesson-check'),
            onPressed: ready && playing.isEditable ? onCheck : null,
            child: switch (status) {
              Submitting() => const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SubmitFailed() => const Text('もう一度送る'),
              Answering() || Checked() || PromptChecked() => const Text('チェック'),
            },
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// A button or a progress indicator under the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (detail case final detail?) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (action case final action?) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
