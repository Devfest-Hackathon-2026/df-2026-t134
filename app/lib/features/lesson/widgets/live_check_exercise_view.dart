import 'package:flutter/material.dart';

import '../../../design/chapter_theme.dart';
import '../../../models/exercise.dart';
import '../../../models/live_check.dart';
import '../hallucination_review.dart';
import '../lesson_state.dart';
import 'hallucination_exercise_view.dart';
import 'live_check_composer.dart';
import 'live_check_generating.dart';
import 'web_source_list.dart';

/// Q10 in the lesson player: the composer, the "generating" state, the AI's
/// answer to investigate (mark sentences, look up sources) and, once
/// checked, every sentence with its verdict.
class LiveCheckExerciseView extends StatelessWidget {
  const LiveCheckExerciseView({
    super.key,
    required this.draft,
    required this.status,
    required this.review,
    required this.onChanged,
    required this.onToggle,
    required this.onLookup,
  });

  final LiveCheckDraft draft;
  final StepStatus status;

  /// Set once the answer is checked.
  final HallucinationReview? review;

  /// Null while nothing can change (waiting or checked).
  final ValueChanged<String>? onChanged;
  final ValueChanged<int>? onToggle;

  /// Returns the sources of the sentence to show, or null (the draft says
  /// why).
  final Future<List<WebSource>?> Function(int index)? onLookup;

  @override
  Widget build(BuildContext context) {
    final session = draft.session;
    if (session == null) {
      return status is Submitting
          ? LiveCheckGenerating(prompt: draft.text.trim())
          : LiveCheckComposer(draft: draft, onChanged: onChanged);
    }
    final review = this.review;
    if (review != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PromptQuote(prompt: draft.text.trim()),
          const SizedBox(height: 12),
          HallucinationExerciseView(
            exercise: draft.asHallucination(),
            selectedIndexes: draft.selectedIndexes,
            review: review,
            onToggle: null,
          ),
        ],
      );
    }
    return _Investigation(
      draft: draft,
      session: session,
      onToggle: onToggle,
      onLookup: onLookup,
    );
  }
}

class _Investigation extends StatelessWidget {
  const _Investigation({
    required this.draft,
    required this.session,
    required this.onToggle,
    required this.onLookup,
  });

  final LiveCheckDraft draft;
  final LiveCheckStarted session;
  final ValueChanged<int>? onToggle;
  final Future<List<WebSource>?> Function(int index)? onLookup;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptQuote(prompt: draft.text.trim()),
        const SizedBox(height: 12),
        _CaseFile(draft: draft, session: session),
        const SizedBox(height: 16),
        for (final sentence in session.sentences)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SentenceCard(
              key: Key('live-check-sentence-${sentence.index}'),
              sentence: sentence,
              draft: draft,
              onToggle: switch (onToggle) {
                final toggle? => () => toggle(sentence.index),
                null => null,
              },
              onLookup: switch (onLookup) {
                final lookup? => () => lookup(sentence.index),
                null => null,
              },
            ),
          ),
      ],
    );
  }
}

class _PromptQuote extends StatelessWidget {
  const _PromptQuote({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('live-check-prompt-quote'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_outline_rounded, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'あなたの質問',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(prompt, style: const TextStyle(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What to find and what is left: errors, marks and lookups.
class _CaseFile extends StatelessWidget {
  const _CaseFile({required this.draft, required this.session});

  final LiveCheckDraft draft;
  final LiveCheckStarted session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimaryContainer;
    return Container(
      key: const Key('live-check-case-file'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, color: on),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI の答え：${draft.exercise.theme}',
                  style: TextStyle(
                    color: on,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'この中の ${session.errorCount} 文が、こっそり書きかえられているよ。'
            'あやしい文は「調べる」で出典を見て、まちがいだと思う文をタップしよう',
            style: TextStyle(color: on, height: 1.5),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'まちがいは ${session.errorCount} こ',
                key: const Key('live-check-error-count'),
                style: TextStyle(color: on, fontWeight: FontWeight.bold),
              ),
              Text(
                'えらんだ文：${draft.selectedIndexes.length} こ',
                key: const Key('live-check-selected-count'),
                style: TextStyle(color: on),
              ),
              Text(
                '🔍 調べる：のこり ${draft.lookupsLeft} 回',
                key: const Key('live-check-lookups-left'),
                style: TextStyle(color: on, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({
    super.key,
    required this.sentence,
    required this.draft,
    required this.onToggle,
    required this.onLookup,
  });

  final Sentence sentence;
  final LiveCheckDraft draft;
  final VoidCallback? onToggle;
  final VoidCallback? onLookup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = sentence.index;
    final selected = draft.selectedIndexes.contains(index);
    final number = index + 1;
    final border = selected ? scheme.primary : scheme.outlineVariant;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border, width: selected ? 3 : 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: onToggle != null,
            selected: selected,
            label: '$number 文目${selected ? '、まちがいとしてえらんだ' : ''}',
            child: InkWell(
              key: Key('live-check-toggle-$index'),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: border,
                        child: Text(
                          '$number',
                          style: TextStyle(
                            color: selected ? Colors.white : scheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sentence.text,
                              style: const TextStyle(fontSize: 17, height: 1.5),
                            ),
                            if (selected)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'まちがいとしてえらんだ',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        selected
                            ? Icons.flag_rounded
                            : Icons.outlined_flag_rounded,
                        color: selected ? scheme.primary : scheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 8, 6),
            child: _LookupRow(index: index, draft: draft, onLookup: onLookup),
          ),
        ],
      ),
    );
  }
}

class _LookupRow extends StatelessWidget {
  const _LookupRow({
    required this.index,
    required this.draft,
    required this.onLookup,
  });

  final int index;
  final LiveCheckDraft draft;
  final VoidCallback? onLookup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final looked = draft.lookups[index];
    final failure = switch (draft.lookupFailure) {
      (index: final i, :final failure) when i == index => failure,
      _ => null,
    };
    final Widget button;
    if (draft.lookingUp == index) {
      button = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (looked != null) {
      return _SentenceSources(index: index, sources: looked);
    } else {
      final canLookUp = draft.canLookUp(index);
      button = TextButton.icon(
        key: Key('live-check-lookup-$index'),
        onPressed: canLookUp ? onLookup : null,
        icon: const Icon(Icons.search_rounded),
        label: Text(draft.lookupsLeft > 0 ? '🔍 調べる' : '調べる回数を使い切ったよ'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: button),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              switch (failure) {
                LookupFailure.noneLeft => '調べる回数を使い切ったよ。ほかの文の出典を手がかりにしよう',
                LookupFailure.failed => '出典を読みこめなかったよ。通信を確認して、もう一度押してね',
              },
              key: Key('live-check-lookup-failure-$index'),
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

/// The pages found for a looked-up sentence, right under it. Never says
/// whether the sentence is right: the learner compares it with the pages.
class _SentenceSources extends StatelessWidget {
  const _SentenceSources({required this.index, required this.sources});

  final int index;
  final List<WebSource> sources;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: Key('live-check-sources-$index'),
        margin: const EdgeInsets.fromLTRB(0, 4, 0, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ChapterPalette.of(context).wash.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${index + 1} 文目の出典（${sources.length} 件）',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'ページを開いて、文と同じことが書いてあるか見くらべよう。'
              '数字・年・名前はとくにしっかり確かめてね。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 8),
            WebSourceList(
              sources: sources,
              emptyText:
                  'この文のもとになったページは見つからなかったよ。'
                  'ほかの文の出典や、教科書でも確かめてみよう。',
            ),
          ],
        ),
      ),
    );
  }
}
