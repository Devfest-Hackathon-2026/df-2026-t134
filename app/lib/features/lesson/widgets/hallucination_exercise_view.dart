import 'package:flutter/material.dart';

import '../../../models/exercise.dart';
import '../hallucination_review.dart';
import 'hallucination_labels.dart';
import 'lesson_colors.dart';

/// Q2: an AI answer split into sentences. The learner taps the sentences
/// they think are wrong; tapping again takes the mark back.
class HallucinationExerciseView extends StatelessWidget {
  const HallucinationExerciseView({
    super.key,
    required this.exercise,
    required this.selectedIndexes,
    required this.review,
    required this.onToggle,
  });

  final HallucinationExercise exercise;
  final Set<int> selectedIndexes;

  /// Set once the answer is checked; marks every sentence with its verdict.
  final HallucinationReview? review;

  /// Null while the marks cannot change (sending or checked).
  final ValueChanged<int>? onToggle;

  @override
  Widget build(BuildContext context) {
    final review = this.review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Instructions(
          topic: exercise.topic,
          errorCount: exercise.errorCount,
          selectedCount: selectedIndexes.length,
        ),
        const SizedBox(height: 16),
        for (final sentence in exercise.sentences)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SentenceCard(
              key: Key('hallucination-sentence-${sentence.index}'),
              sentence: sentence,
              selected: selectedIndexes.contains(sentence.index),
              review: review?.sentences[sentence.index],
              onTap: switch (onToggle) {
                final toggle? => () => toggle(sentence.index),
                null => null,
              },
            ),
          ),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions({
    required this.topic,
    required this.errorCount,
    required this.selectedCount,
  });

  final String topic;
  final int errorCount;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('hallucination-instructions'),
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
              Icon(Icons.smart_toy_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI の答え：$topic',
                  key: const Key('hallucination-topic'),
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'まちがっている文をタップしよう',
            style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'まちがいは $errorCount こ',
                key: const Key('hallucination-error-count'),
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'えらんだ文：$selectedCount こ',
                key: const Key('hallucination-selected-count'),
                style: TextStyle(color: scheme.onPrimaryContainer),
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
    required this.selected,
    required this.review,
    required this.onTap,
  });

  final Sentence sentence;
  final bool selected;

  /// Null until the answer is checked.
  final SentenceReview? review;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verdict = review?.verdict;
    final (border, background) = switch (verdict) {
      SentenceVerdict.found => (
        LessonColors.correct,
        LessonColors.correctBackground,
      ),
      SentenceVerdict.missed || SentenceVerdict.falseAlarm => (
        LessonColors.incorrect,
        LessonColors.incorrectBackground,
      ),
      SentenceVerdict.untouched => (scheme.outlineVariant, scheme.surface),
      null when selected => (scheme.primary, scheme.primaryContainer),
      null => (scheme.outlineVariant, scheme.surface),
    };
    final number = sentence.index + 1;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$number 文目${selected ? '、まちがいとしてえらんだ' : ''}',
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: border,
            width: selected || verdict == SentenceVerdict.missed ? 3 : 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: border,
                    child: Text(
                      '$number',
                      style: TextStyle(
                        color:
                            verdict == SentenceVerdict.untouched ||
                                (verdict == null && !selected)
                            ? scheme.onSurface
                            : Colors.white,
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
                        if (review case final review?) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SentenceVerdictLabel(verdict: review.verdict),
                              if (review.error case final error?)
                                ErrorTypeTag(type: error.errorType),
                            ],
                          ),
                        ] else if (selected) ...[
                          const SizedBox(height: 8),
                          Text(
                            'まちがいとしてえらんだ',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (review == null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? Icons.flag_rounded
                          : Icons.outlined_flag_rounded,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
