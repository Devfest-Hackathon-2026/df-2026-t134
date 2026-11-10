import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/chapter_theme.dart';
import '../../../design/motion.dart';
import '../../../models/answer.dart';
import '../../../models/exercise.dart';
import '../../../models/story.dart';
import '../lesson_state.dart';
import 'choice_exercise_view.dart';
import 'scene_voice_button.dart';
import 'story_picture.dart';

/// A picture-story (kamishibai): one scene at a time, then 「ユイはどうする？」
/// with the options, then the chosen option's outcome. The buttons that move
/// on are in `StoryActionBar`; tapping the scene also moves on.
class StoryExerciseView extends StatelessWidget {
  const StoryExerciseView({
    super.key,
    required this.draft,
    required this.result,
    required this.onAdvance,
    required this.onSelect,
  });

  final StoryDraft draft;

  /// Set once the choice is checked: its outcome plays, then the options are
  /// marked.
  final StoryResult? result;

  /// Shows the next scene; null when tapping the scene does nothing (the
  /// question or the end of the outcome is on screen, or it is sending).
  final VoidCallback? onAdvance;

  /// Null while the options cannot be changed.
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final exercise = draft.exercise;
    final result = this.result;
    final scenes = [...exercise.scenes, ...?result?.outcome];
    final int index;
    final String counter;
    if (result != null) {
      final last = result.outcome.length - 1;
      final shown = draft.outcomeIndex.clamp(0, last);
      index = exercise.scenes.length + shown;
      counter = 'そのあと ${shown + 1} / ${result.outcome.length}';
    } else if (!draft.isDeciding) {
      index = draft.sceneIndex;
      counter = '場面 ${index + 1} / ${exercise.scenes.length}';
    } else {
      index = exercise.scenes.length - 1;
      counter = 'どうする？';
    }
    final showOptions = draft.isDeciding && result == null;
    final showMarks = result != null && draft.outcomeDone(result);
    return Column(
      key: const Key('story-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StoryTitle(title: exercise.title, counter: counter),
        const SizedBox(height: 12),
        if (result != null) ...[
          _ChosenOption(
            text: exercise.options
                .firstWhere((o) => o.id == draft.selectedOptionId)
                .text,
          ),
          const SizedBox(height: 12),
        ],
        _SceneSwitcher(
          index: index,
          child: SceneCard(
            key: ValueKey('story-scene-$index'),
            scene: scenes[index],
            picture: pictureAt(scenes, index),
            onTap: onAdvance,
          ),
        ),
        if (showOptions || showMarks) ...[
          const SizedBox(height: 20),
          Text(
            exercise.question,
            key: const Key('story-question'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ChoiceExerciseView(
            exercise: ChoiceExercise(
              id: exercise.id,
              lessonId: exercise.lessonId,
              question: exercise.question,
              options: exercise.options,
            ),
            selectedOptionId: draft.selectedOptionId,
            result: result == null
                ? null
                : ChoiceResult(
                    correctOptionId: result.bestOptionId,
                    explanation: result.explanation,
                  ),
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }
}

class _StoryTitle extends StatelessWidget {
  const _StoryTitle({required this.title, required this.counter});

  final String title;
  final String counter;

  @override
  Widget build(BuildContext context) {
    final palette = ChapterPalette.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, color: palette.accent, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                key: const Key('story-title'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        Text(
          counter,
          key: const Key('story-counter'),
          style: const TextStyle(color: ChapterPalette.muted),
        ),
      ],
    );
  }
}

/// 「えらんだ：…」 above the outcome.
class _ChosenOption extends StatelessWidget {
  const _ChosenOption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('story-chosen'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.subdirectory_arrow_right_rounded, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('えらんだ：$text')),
        ],
      ),
    );
  }
}

/// The calm page turn between scenes: a 320ms fade with a slight slide, or
/// an instant change when motion is reduced.
class _SceneSwitcher extends ConsumerWidget {
  const _SceneSwitcher({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final still = reduceMotion(context, ref);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.04, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// One panel: the picture, who speaks, the line (always shown) and the
/// optional voice button. Tapping it moves on when [onTap] is set.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.scene,
    required this.picture,
    required this.onTap,
  });

  final Scene scene;

  /// The scene's picture or the one it keeps from an earlier scene.
  final Illustration? picture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audioPath = scene.audioPath;
    return Semantics(
      button: onTap != null,
      onTapHint: onTap == null ? null : 'つぎの場面へ',
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Keeps room for the line on short or wide screens.
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .38,
                    ),
                    child: StoryPicture(illustration: picture),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SpeakerLabel(speaker: scene.speaker),
                      ),
                    ),
                    if (audioPath != null)
                      SceneVoiceButton(audioPath: audioPath),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  // Text renders the `\n` in lines as line breaks.
                  child: Text(
                    scene.text,
                    key: const Key('story-line'),
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.7,
                      color: scene.speaker == Speaker.narrator
                          ? ChapterPalette.muted
                          : ChapterPalette.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who speaks: an icon and the name (never color alone).
class SpeakerLabel extends StatelessWidget {
  const SpeakerLabel({super.key, required this.speaker});

  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final palette = ChapterPalette.of(context);
    final icon = switch (speaker) {
      Speaker.narrator => Icons.auto_stories_rounded,
      Speaker.mascot => Icons.smart_toy_rounded,
      Speaker.student => Icons.face_rounded,
      Speaker.friend => Icons.sentiment_satisfied_alt_rounded,
      Speaker.teacher => Icons.school_rounded,
      Speaker.ai => Icons.tablet_android_rounded,
    };
    final emphasized = speaker != Speaker.narrator;
    return Container(
      key: Key('story-speaker-${speaker.wireName}'),
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: BoxDecoration(
        color: emphasized ? palette.wash : ChapterPalette.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: emphasized ? palette.accent : ChapterPalette.muted,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              speaker.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
