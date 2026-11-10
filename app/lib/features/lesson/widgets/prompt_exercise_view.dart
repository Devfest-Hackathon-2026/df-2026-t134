import 'package:flutter/material.dart';

import '../../../models/prompt_evaluation.dart';
import '../lesson_state.dart';
import '../personal_info_check.dart';

/// Q4: the task, a reminder of the five elements, and the text field with a
/// live character counter. Shows the server's "blocked" message and a local
/// personal-information warning while the learner edits.
class PromptExerciseView extends StatefulWidget {
  const PromptExerciseView({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PromptDraft draft;

  /// Null while the text cannot change (sending or graded).
  final ValueChanged<String>? onChanged;

  @override
  State<PromptExerciseView> createState() => _PromptExerciseViewState();
}

class _PromptExerciseViewState extends State<PromptExerciseView> {
  late final TextEditingController _text = TextEditingController(
    text: widget.draft.text,
  );

  @override
  void didUpdateWidget(PromptExerciseView oldWidget) {
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
    final editable = widget.onChanged != null;
    final found = editable
        ? findPersonalInfo(draft.text)
        : const <PersonalInfoKind>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TaskCard(task: exercise.task),
        const SizedBox(height: 12),
        const _ElementsHint(),
        if (draft.blocked case final blocked? when editable) ...[
          const SizedBox(height: 16),
          PromptBlockedNotice(blocked: blocked),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('prompt-input'),
          controller: _text,
          readOnly: !editable,
          onChanged: widget.onChanged,
          minLines: 5,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          // Flutter counts grapheme clusters here; the counter below and
          // PromptDraft.isTooLong count code points like the API.
          maxLength: exercise.maxLength,
          buildCounter: (
            context, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => null,
          style: const TextStyle(fontSize: 17, height: 1.6),
          decoration: const InputDecoration(
            labelText: 'AI へのプロンプト',
            alignLabelWithHint: true,
            hintText: '例：あなたは〇〇です。〜のために、〜を 3 つ、箇条書きで教えて',
            hintMaxLines: 3,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            '${draft.length} / ${exercise.maxLength} 文字',
            key: const Key('prompt-counter'),
            style: TextStyle(
              color: draft.isTooLong ? scheme.error : scheme.onSurfaceVariant,
              fontWeight: draft.isTooLong ? FontWeight.bold : null,
            ),
          ),
        ),
        if (draft.isTooLong && editable)
          Text(
            '${exercise.maxLength} 文字以内にしよう',
            key: const Key('prompt-too-long'),
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final String task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('prompt-task'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'お題',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(task, style: const TextStyle(fontSize: 17, height: 1.6)),
        ],
      ),
    );
  }
}

/// The five elements of a good prompt, as a reminder (not graded here).
class _ElementsHint extends StatelessWidget {
  const _ElementsHint();

  static const _elements = [
    ('役割', 'AI にだれになってほしい？'),
    ('目的', '何のために、何をしてほしい？'),
    ('前提', 'どんな状況・相手？'),
    ('条件', '数・長さ・してほしくないこと'),
    ('出力形式', '箇条書き・表など'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('prompt-elements-hint'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ヒント：この 5 つを入れてみよう',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (name, question) in _elements)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A bullet, not a checkbox: the list is not tappable.
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Icon(Icons.circle, size: 8, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: '　$question',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
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

/// Before sending: the text seems to contain personal information.
class PersonalInfoWarning extends StatelessWidget {
  const PersonalInfoWarning({super.key, required this.kinds});

  final List<PersonalInfoKind> kinds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Notice(
      key: const Key('prompt-personal-info-warning'),
      icon: Icons.shield_outlined,
      color: scheme.error,
      title: '個人情報が入っていないかな？',
      body: personalInfoAdvice(kinds),
    );
  }
}

/// What to do about [kinds]; shared by the inline warning and the dialog.
String personalInfoAdvice(List<PersonalInfoKind> kinds) =>
    '${kinds.map((k) => k.label).join('・')}のようなものが入っているみたい。'
    'AI に個人情報を送るのはやめておこう。その部分を消すか「〇〇」に置きかえてね';

/// The server did not grade the prompt: a teaching moment, not an error.
class PromptBlockedNotice extends StatelessWidget {
  const PromptBlockedNotice({super.key, required this.blocked});

  final PromptBlocked blocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personal = blocked.reasons.contains(PromptBlockReason.personalInfo);
    return _Notice(
      key: const Key('prompt-blocked'),
      icon: personal ? Icons.shield_outlined : Icons.edit_note_rounded,
      color: scheme.primary,
      title: personal ? '個人情報は AI に送らないようにしよう' : '送る前に見直してみよう',
      body: [
        if (blocked.message.isNotEmpty) blocked.message,
        'プロンプトは採点も記録もされていないよ。書き直してから、もう一度送ってね',
      ].join('\n'),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
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
                  Text(body, style: const TextStyle(height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
