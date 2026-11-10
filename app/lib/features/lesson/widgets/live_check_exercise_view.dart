import 'package:flutter/material.dart';

import '../../../design/chapter_theme.dart';
import '../../../models/answer_mark.dart';
import '../../../models/live_check.dart';
import '../hallucination_review.dart';
import '../lesson_state.dart';
import 'answer_passage.dart';
import 'live_check_composer.dart';
import 'live_check_generating.dart';
import 'web_source_list.dart';

class LiveCheckExerciseView extends StatelessWidget {
  const LiveCheckExerciseView({
    super.key,
    required this.draft,
    required this.status,
    required this.review,
    required this.onChanged,
    required this.onToggle,
    required this.onLookup,
    this.onMark,
    this.onRemove,
    this.onNoErrors,
  });
  final LiveCheckDraft draft;
  final StepStatus status;
  final HallucinationReview? review;
  final ValueChanged<String>? onChanged;
  final ValueChanged<int>? onToggle;
  final Future<List<WebSource>?> Function(int)? onLookup;
  final ValueChanged<AnswerMark>? onMark;
  final ValueChanged<AnswerMark>? onRemove;
  final VoidCallback? onNoErrors;
  @override
  Widget build(BuildContext context) {
    final session = draft.session;
    if (session == null) {
      return status is Submitting
          ? LiveCheckGenerating(prompt: draft.text.trim())
          : LiveCheckComposer(draft: draft, onChanged: onChanged);
    }
    final editable = review == null && (onMark != null || onToggle != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('あなたの質問', style: Theme.of(context).textTheme.titleSmall),
        Text(
          draft.text.trim(),
          key: const Key('live-check-prompt-quote'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const Text('質問に対して正しい答えが返ってきているか確かめよう。'),
        const SizedBox(height: 12),
        AnswerPassage(
          key: ValueKey(session.sessionId),
          prefix: 'live-check',
          sentences: session.sentences,
          marks: draft.selectionMarks,
          confirmedNoErrors: draft.confirmedNoErrors,
          review: review,
          onMark: !editable
              ? null
              : onMark ??
                    (mark) {
                      for (final i in markedIndexes(session.sentences, [
                        mark,
                      ])) {
                        if (!draft.selectedIndexes.contains(i)) onToggle!(i);
                      }
                    },
          onRemove: !editable
              ? null
              : onRemove ??
                    (mark) {
                      for (final i in markedIndexes(session.sentences, [
                        mark,
                      ])) {
                        if (draft.selectedIndexes.contains(i)) {
                          onToggle?.call(i);
                        }
                      }
                    },
          onNoErrors: editable ? onNoErrors : null,
          onLookup: !editable || onLookup == null
              ? null
              : (indexes) async {
                  int? index = indexes.singleOrNull;
                  if (indexes.length > 1) {
                    index = await showDialog<int>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: const Text('確かめる内容を選ぼう'),
                        children: [
                          for (final i in indexes)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, i),
                              child: Text(session.sentences[i].text),
                            ),
                        ],
                      ),
                    );
                  }
                  if (index != null &&
                      (draft.canLookUp(index) ||
                          draft.lookups.containsKey(index))) {
                    await onLookup!(index);
                  }
                },
        ),
        if (editable) ...[
          const SizedBox(height: 8),
          Text(
            '出典を調べる：のこり ${draft.lookupsLeft} 回',
            key: const Key('live-check-lookups-left'),
          ),
          if (draft.lookingUp != null) const LinearProgressIndicator(),
          if (draft.lookupFailure case (:final index, :final failure))
            Text(
              failure == LookupFailure.noneLeft
                  ? '調べる回数を使い切ったよ。確認した出典を見くらべよう。'
                  : '出典を読みこめなかったよ。通信を確認して、もう一度試してね。',
              key: Key('live-check-lookup-failure-$index'),
            ),
          for (final entry in draft.lookups.entries) ...[
            const SizedBox(height: 12),
            Text('「${session.sentences[entry.key].text}」'),
            _SentenceSources(index: entry.key, sources: entry.value),
          ],
        ],
      ],
    );
  }
}

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
                    '確かめた出典（${sources.length} 件）',
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
