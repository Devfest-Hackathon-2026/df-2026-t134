import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../lesson_state.dart';
import '../personal_info_check.dart';
import 'prompt_exercise_view.dart';

/// Why a prompt could not be graded, as the learner should understand it.
enum PromptFailure {
  /// 503 `upstream_unavailable`: AI grading is off or down (the normal case
  /// on a local stack). Retry later or skip.
  aiUnavailable,

  /// 429 `rate_limited`: the daily limit is used up. Only skipping helps.
  dailyLimit,

  /// Network errors, other 5xx and anything unexpected. Retry.
  other;

  static PromptFailure of(Object error) => switch (error) {
    ApiException(code: ApiErrorCode.upstreamUnavailable) => aiUnavailable,
    ApiException(code: ApiErrorCode.rateLimited) => dailyLimit,
    _ => other,
  };
}

/// 「AI に採点してもらう」 under a prompt exercise, with a personal-info check
/// before sending, and the explanation, retry and skip when grading failed.
class PromptSendBar extends StatelessWidget {
  const PromptSendBar({
    super.key,
    required this.draft,
    required this.status,
    required this.onSend,
    required this.onSkip,
  });

  final PromptDraft draft;
  final StepStatus status;
  final VoidCallback onSend;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure = switch (status) {
      SubmitFailed(:final error) => PromptFailure.of(error),
      _ => null,
    };
    final sending = status is Submitting;
    final ready = draft.promptToSend != null && !sending;
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
            _FailureMessage(failure: failure),
            const SizedBox(height: 12),
          ] else if (!ready && !sending) ...[
            Text(
              draft.isTooLong
                  ? '${draft.exercise.maxLength} 文字以内にしたら送れるよ'
                  : 'プロンプトを書いたら、AI に採点してもらおう',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
          if (failure != PromptFailure.dailyLimit)
            FilledButton(
              key: const Key('prompt-send'),
              onPressed: ready ? () => _confirmAndSend(context) : null,
              child: sending
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Text(failure == null ? 'AI に採点してもらう' : 'もう一度送る'),
            ),
          if (failure != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('prompt-skip'),
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
  Future<void> _confirmAndSend(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final kinds = findPersonalInfo(draft.text);
    if (kinds.isEmpty) {
      onSend();
      return;
    }
    final sendAnyway = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('prompt-personal-info-dialog'),
        icon: const Icon(Icons.shield_outlined),
        title: const Text('送る前にチェック'),
        content: SingleChildScrollView(child: Text(personalInfoAdvice(kinds))),
        actions: [
          TextButton(
            key: const Key('prompt-send-anyway'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('このまま送る'),
          ),
          FilledButton(
            key: const Key('prompt-edit-again'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('書き直す'),
          ),
        ],
      ),
    );
    if (sendAnyway ?? false) {
      onSend();
    }
  }
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage({required this.failure});

  final PromptFailure failure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title, detail) = switch (failure) {
      PromptFailure.aiUnavailable => (
        Icons.bedtime_outlined,
        scheme.primary,
        'いまは AI の採点がお休み中だよ',
        '書いたプロンプトはそのまま残っているよ。少し待ってもう一度送るか、今回はスキップして先に進もう',
      ),
      PromptFailure.dailyLimit => (
        Icons.hourglass_bottom_rounded,
        scheme.primary,
        '今日の AI 採点はここまで',
        '1 日に使える回数を使い切ったよ。また明日ためしてね。今回はスキップして先に進もう',
      ),
      PromptFailure.other => (
        Icons.wifi_off_rounded,
        scheme.error,
        '送信できませんでした',
        'プロンプトはそのままだよ。通信を確認して、もう一度送ってね',
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        key: Key('prompt-failure-${failure.name}'),
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
