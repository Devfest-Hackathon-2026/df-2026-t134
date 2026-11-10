import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../lesson_state.dart';

/// Whether [playing] is a story whose chosen outcome is still playing (the
/// feedback panel comes after it).
bool isStoryOutcomePlaying(LessonPlaying playing) =>
    switch ((playing.draft, playing.status)) {
      (
        final StoryDraft draft,
        Checked(response: SubmitAnswerResponse(:final StoryResult result)),
      ) =>
        !draft.outcomeDone(result),
      _ => false,
    };

/// The bottom bar of a story before its feedback: 「つぎへ」 through the
/// scenes (and 「とばす」 to the question), 「これにする」 with the send error
/// and retry, then 「つぎへ」 through the outcome.
class StoryActionBar extends StatelessWidget {
  const StoryActionBar({
    super.key,
    required this.playing,
    required this.onNextScene,
    required this.onSkipScenes,
    required this.onChoose,
  });

  final LessonPlaying playing;
  final VoidCallback onNextScene;
  final VoidCallback onSkipScenes;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = playing.draft as StoryDraft;
    final status = playing.status;
    final children = switch (status) {
      Checked(response: SubmitAnswerResponse(:final StoryResult result)) => [
        FilledButton.icon(
          key: const Key('story-next'),
          onPressed: onNextScene,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            draft.outcomeIndex + 1 >= result.outcome.length ? 'けっかを見る' : 'つぎへ',
          ),
        ),
      ],
      _ when !draft.isDeciding => [
        FilledButton.icon(
          key: const Key('story-next'),
          onPressed: onNextScene,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('つぎへ'),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('story-skip'),
          onPressed: onSkipScenes,
          child: const Text('お話をとばして、えらぶ'),
        ),
      ],
      _ => [
        if (status is SubmitFailed) ...[
          Row(
            key: const Key('lesson-submit-error'),
            children: [
              Icon(Icons.wifi_off_rounded, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '送信できませんでした。えらんだ答えはそのままだよ。もう一度送ってね',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ] else if (draft.selectedOptionId == null) ...[
          Text(
            'いちばんいいと思うものを 1 つえらんでね',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          key: const Key('lesson-check'),
          onPressed: draft.toAnswer() != null && playing.isEditable
              ? onChoose
              : null,
          child: switch (status) {
            Submitting() => const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SubmitFailed() => const Text('もう一度送る'),
            _ => const Text('これにする'),
          },
        ),
      ],
    };
    return Container(
      key: const Key('story-action-bar'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
