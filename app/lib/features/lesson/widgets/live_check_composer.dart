import 'package:flutter/material.dart';

import '../../../models/live_check.dart';
import '../../../models/prompt_evaluation.dart';
import '../lesson_state.dart';
import '../personal_info_check.dart';
import 'prompt_exercise_view.dart' show PersonalInfoWarning;

/// Q10, before the AI answers: the theme, how the exercise works, example
/// questions to tap, and the prompt field with a live character counter.
/// Shows the server's "blocked" message and the local personal-information
/// warning while the learner edits.
class LiveCheckComposer extends StatefulWidget {
  const LiveCheckComposer({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final LiveCheckDraft draft;

  /// Null while the text cannot change (waiting for the AI).
  final ValueChanged<String>? onChanged;

  @override
  State<LiveCheckComposer> createState() => _LiveCheckComposerState();
}

class _LiveCheckComposerState extends State<LiveCheckComposer> {
  late final TextEditingController _text = TextEditingController(
    text: widget.draft.text,
  );

  @override
  void didUpdateWidget(LiveCheckComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The draft is the source of truth; typing keeps both equal.
    if (widget.draft.text != _text.text) {
      _text.text = widget.draft.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;
    final exercise = draft.exercise;
    final onChanged = widget.onChanged;
    final found = onChanged == null
        ? const <PersonalInfoKind>[]
        : findPersonalInfo(draft.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HowItWorks(theme: exercise.theme, errorCount: exercise.errorCount),
        if (draft.blocked case final blocked? when onChanged != null) ...[
          const SizedBox(height: 16),
          LiveCheckBlockedNotice(blocked: blocked),
        ],
        const SizedBox(height: 16),
        Text(
          '質問の例（タップすると入るよ）',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, suggestion) in exercise.suggestions.indexed)
              ActionChip(
                key: Key('live-check-suggestion-$i'),
                avatar: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(suggestion, softWrap: true),
                onPressed: onChanged == null
                    ? null
                    : () {
                        _text.text = suggestion;
                        onChanged(suggestion);
                      },
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('live-check-input'),
          controller: _text,
          readOnly: onChanged == null,
          onChanged: onChanged,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          // The counter below counts code points like the API.
          maxLength: exercise.maxLength,
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => null,
          style: const TextStyle(fontSize: 17, height: 1.6),
          decoration: InputDecoration(
            labelText: 'AI への質問',
            alignLabelWithHint: true,
            hintText: '例：${exercise.theme}について、〜を教えて',
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            '${draft.length} / ${exercise.maxLength} 文字',
            key: const Key('live-check-counter'),
            style: TextStyle(
              color: draft.isTooLong ? scheme.error : scheme.onSurfaceVariant,
              fontWeight: draft.isTooLong ? FontWeight.bold : null,
            ),
          ),
        ),
        if (draft.isTooLong && onChanged != null)
          Text(
            '${exercise.maxLength} 文字以内にしよう',
            key: const Key('live-check-too-long'),
            textAlign: TextAlign.end,
            style: TextStyle(color: scheme.error),
          ),
        if (found.isNotEmpty) ...[
          const SizedBox(height: 12),
          PersonalInfoWarning(kinds: found),
        ],
      ],
    );
  }
}

/// The three steps of the exercise, so the learner knows what is coming.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.theme, required this.errorCount});

  final String theme;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      (Icons.edit_rounded, '「$theme」について、AI に質問を書く'),
      (
        Icons.travel_explore_rounded,
        'AI が Google 検索で調べて答える（まちがいがこっそり $errorCount こ）',
      ),
      (Icons.search_rounded, '「調べる」で出典を見て、まちがいを見つける'),
    ];
    return Container(
      key: const Key('live-check-how'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'テーマ：$theme',
            key: const Key('live-check-theme'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
            ),
          ),
          for (final (i, (icon, text)) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${i + 1}. $text',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The server did not send the prompt to the AI: a teaching moment.
class LiveCheckBlockedNotice extends StatelessWidget {
  const LiveCheckBlockedNotice({super.key, required this.blocked});

  final LiveCheckBlocked blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reasons = blocked.reasons;
    final (icon, title) = reasons.contains(PromptBlockReason.personalInfo)
        ? (Icons.shield_outlined, '個人情報は AI に送らないようにしよう')
        : reasons.contains(PromptBlockReason.offTopic)
        ? (Icons.explore_outlined, 'テーマからはなれているみたい')
        : (Icons.edit_note_rounded, '送る前に見直してみよう');
    final color = scheme.primary;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('live-check-blocked'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          border: Border.all(color: color.withValues(alpha: .45), width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (blocked.message.isNotEmpty) blocked.message,
                      '質問は記録されていないよ。書き直してから、もう一度送ってね',
                    ].join('\n'),
                    style: const TextStyle(height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
