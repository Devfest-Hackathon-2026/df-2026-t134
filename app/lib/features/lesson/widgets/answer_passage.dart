import 'package:flutter/material.dart';

import '../../../models/answer_mark.dart';
import '../../../models/exercise.dart';
import '../hallucination_review.dart';
import 'lesson_colors.dart';

/// A continuous answer. Selection offsets remain exact even if words repeat.
class AnswerPassage extends StatefulWidget {
  const AnswerPassage({
    super.key,
    required this.prefix,
    required this.sentences,
    required this.marks,
    required this.confirmedNoErrors,
    this.review,
    this.onMark,
    this.onRemove,
    this.onNoErrors,
    this.onLookup,
  });
  final String prefix;
  final List<Sentence> sentences;
  final List<AnswerMark> marks;
  final bool confirmedNoErrors;
  final HallucinationReview? review;
  final ValueChanged<AnswerMark>? onMark;
  final ValueChanged<AnswerMark>? onRemove;
  final VoidCallback? onNoErrors;
  final ValueChanged<List<int>>? onLookup;
  @override
  State<AnswerPassage> createState() => _AnswerPassageState();
}

class _AnswerPassageState extends State<AnswerPassage> {
  late final _MarkedTextController _text = _MarkedTextController(
    answerPassage(widget.sentences),
  );
  @override
  void didUpdateWidget(covariant AnswerPassage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = answerPassage(widget.sentences);
    if (_text.text != value) _text.text = value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  AnswerMark? get selectedMark {
    final selection = _text.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    var start = selection.start;
    var end = selection.end;
    while (start < end && _text.text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && _text.text[end - 1].trim().isEmpty) {
      end--;
    }
    return start == end ? null : AnswerMark(start, end);
  }

  void _mark() {
    final mark = selectedMark;
    if (mark != null && !widget.marks.contains(mark)) widget.onMark?.call(mark);
    ContextMenuController.removeAny();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _text.highlights = [
      for (final mark in widget.marks) (mark, scheme.primaryContainer),
      if (widget.review case final review?)
        for (final sentence in review.sentences)
          if (sentence.verdict != SentenceVerdict.untouched)
            (
              sentenceMark(widget.sentences, sentence.sentence.index),
              sentence.verdict == SentenceVerdict.found
                  ? LessonColors.correctBackground
                  : LessonColors.incorrectBackground,
            ),
    ];
    final editable = widget.onMark != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(12),
            ),
          ),
          child: TextField(
            key: Key('${widget.prefix}-answer'),
            controller: _text,
            readOnly: true,
            showCursor: false,
            maxLines: null,
            minLines: 1,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontSize: 18, height: 1.8),
            decoration: const InputDecoration(
              labelText: 'AI の回答',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              filled: false,
            ),
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: state.contextMenuAnchors,
                  buttonItems: [
                    if (editable && selectedMark != null)
                      ContextMenuButtonItem(
                        label: 'この部分が間違い',
                        onPressed: _mark,
                      ),
                    ...state.contextMenuButtonItems,
                  ],
                ),
          ),
        ),
        if (editable) ...[
          const SizedBox(height: 10),
          const Text('回答は正しいかな？ 気になる部分を長押し・ドラッグして選び、出典と見くらべよう。'),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, _, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('${widget.prefix}-mark-selected'),
                  onPressed: selectedMark != null ? _mark : null,
                  icon: const Icon(Icons.border_color_outlined),
                  label: const Text('この部分が間違い'),
                ),
                if (widget.onLookup != null)
                  OutlinedButton.icon(
                    key: Key('${widget.prefix}-lookup-selected'),
                    onPressed: selectedMark == null
                        ? null
                        : () => widget.onLookup!(
                            markedIndexes(widget.sentences, [
                              selectedMark!,
                            ]).toList()..sort(),
                          ),
                    icon: const Icon(Icons.search),
                    label: const Text('選んだ部分を調べる'),
                  ),
              ],
            ),
          ),
          if (widget.marks.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final mark in widget.marks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InputChip(
                  key: Key('${widget.prefix}-mark-${mark.start}-${mark.end}'),
                  label: Text(
                    '「${_text.text.substring(mark.start, mark.end)}」',
                  ),
                  deleteButtonTooltipMessage: 'この指定を取り消す',
                  onDeleted: widget.onRemove == null
                      ? null
                      : () => widget.onRemove!(mark),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Semantics(
            selected: widget.confirmedNoErrors,
            child: OutlinedButton.icon(
              key: Key('${widget.prefix}-no-errors'),
              onPressed: widget.onNoErrors,
              style: OutlinedButton.styleFrom(
                backgroundColor: widget.confirmedNoErrors
                    ? scheme.primaryContainer
                    : null,
              ),
              icon: Icon(
                widget.confirmedNoErrors
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
              ),
              label: const Text('誤りはない'),
            ),
          ),
          if (widget.confirmedNoErrors) const Text('「誤りはない」を選択中。確認できたら回答を送ろう。'),
        ],
      ],
    );
  }
}

class _MarkedTextController extends TextEditingController {
  _MarkedTextController(String text) : super(text: text);
  List<(AnswerMark, Color)> highlights = [];
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final cuts = <int>{
      0,
      text.length,
      for (final (mark, _) in highlights) ...[mark.start, mark.end],
    }.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < cuts.length - 1; i++)
          TextSpan(
            text: text.substring(cuts[i], cuts[i + 1]),
            style: TextStyle(
              backgroundColor: highlights
                  .where(
                    (h) => h.$1.start <= cuts[i] && h.$1.end >= cuts[i + 1],
                  )
                  .lastOrNull
                  ?.$2,
            ),
          ),
      ],
    );
  }
}
