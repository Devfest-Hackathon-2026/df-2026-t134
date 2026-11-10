import 'package:flutter/material.dart';

import '../lesson_state.dart';
import '../personal_info_check.dart';
import 'prompt_exercise_view.dart' show personalInfoAdvice;
import 'prompt_send_bar.dart' show PromptFailure;

/// The actions under a live check: 「AI に質問する」 (with a personal-info
/// check before sending) while composing, 「これで決定」 while investigating,
/// and the explanation, retry and skip when something failed.
class LiveCheckActionBar extends StatelessWidget {
  const LiveCheckActionBar({
    super.key,
    required this.draft,
    required this.status,
    required this.onStart,
    required this.onCheck,
    required this.onSkip,
  });

  final LiveCheckDraft draft;
  final StepStatus status;
  final VoidCallback onStart;
  final VoidCallback onCheck;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure = switch (status) {
      SubmitFailed(:final error) => PromptFailure.of(error),
      _ => null,
    };
    final sending = status is Submitting;
    final composing = draft.isComposing;
    final ready =
        !sending &&
        (composing ? draft.promptToSend != null : draft.toAnswer() != null);
    final hint = composing
        ? (draft.isTooLong
              ? '${draft.exercise.maxLength} 文字以内にしたら送れるよ'
              : '質問を書くか、例をタップしてから AI に聞こう')
        : 'まちがいだと思う文をタップしてから決定しよう';
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
          if (failure != null) ...[
            _FailureMessage(failure: failure, composing: composing),
            const SizedBox(height: 12),
          ] else if (!ready && !sending) ...[
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
          if (failure != PromptFailure.dailyLimit)
            FilledButton(
              key: Key(composing ? 'live-check-send' : 'live-check-submit'),
              onPressed: ready
                  ? (composing ? () => _confirmAndStart(context) : onCheck)
                  : null,
              child: sending
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Text(switch ((composing, failure == null)) {
                      (true, true) => 'AI に質問する',
                      (false, true) => 'これで決定',
                      (_, false) => 'もう一度送る',
                    }),
            ),
          if (failure != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('live-check-skip'),
              onPressed: onSkip,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('今回はスキップ'),
            ),
          ],
        ],
      ),
    );
  }

  /// Sends at once, or first asks when the text looks like it contains
  /// personal information (editing is the recommended answer).
  Future<void> _confirmAndStart(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final kinds = findPersonalInfo(draft.text);
    if (kinds.isEmpty) {
      onStart();
      return;
    }
    final sendAnyway = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('live-check-personal-info-dialog'),
        icon: const Icon(Icons.shield_outlined),
        title: const Text('送る前にチェック'),
        content: SingleChildScrollView(child: Text(personalInfoAdvice(kinds))),
        actions: [
          TextButton(
            key: const Key('live-check-send-anyway'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('このまま送る'),
          ),
          FilledButton(
            key: const Key('live-check-edit-again'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('書き直す'),
          ),
        ],
      ),
    );
    if (sendAnyway ?? false) {
      onStart();
    }
  }
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage({required this.failure, required this.composing});

  final PromptFailure failure;

  /// Whether the question (not the answer) could not be sent.
  final bool composing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kept = composing ? '書いた質問' : 'えらんだ文';
    final (icon, color, title, detail) = switch (failure) {
      PromptFailure.aiUnavailable => (
        Icons.bedtime_outlined,
        scheme.primary,
        'いまは AI がお休み中だよ',
        '$keptはそのまま残っているよ。少し待ってもう一度送るか、今回はスキップして先に進もう',
      ),
      PromptFailure.dailyLimit => (
        Icons.hourglass_bottom_rounded,
        scheme.primary,
        '今日の「AI に質問」はここまで',
        '1 日に使える回数を使い切ったよ。また明日ためしてね。今回はスキップして先に進もう',
      ),
      PromptFailure.other => (
        Icons.wifi_off_rounded,
        scheme.error,
        '送信できませんでした',
        '$keptはそのままだよ。通信を確認して、もう一度送ってね',
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        key: Key('live-check-failure-${failure.name}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
