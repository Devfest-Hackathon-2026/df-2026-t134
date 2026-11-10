import 'package:flutter/material.dart';

import '../hallucination_review.dart';
import 'hallucination_labels.dart';

/// The hallucination part of the feedback panel: how many errors were found,
/// then each wrong sentence (found or missed) with its kind, the correction
/// and a tip, then the correct sentences that were tapped.
///
/// The texts here are what the mascot could read aloud later (PR-15).
class HallucinationFeedbackView extends StatelessWidget {
  const HallucinationFeedbackView({super.key, required this.review});

  final HallucinationReview review;

  @override
  Widget build(BuildContext context) {
    final falseAlarms = review.falseAlarms.toList();
    return Column(
      key: const Key('hallucination-feedback'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'まちがい ${review.errorCount} こ中 ${review.foundCount} こ見つけたよ',
          key: const Key('hallucination-feedback-summary'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        for (final sentence in review.errors) ...[
          const SizedBox(height: 12),
          _ErrorEntry(
            key: Key('hallucination-feedback-error-${sentence.sentence.index}'),
            sentence: sentence,
          ),
        ],
        if (falseAlarms.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final sentence in falseAlarms)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FalseAlarmEntry(
                key: Key(
                  'hallucination-feedback-false-alarm-${sentence.sentence.index}',
                ),
                sentence: sentence,
              ),
            ),
        ],
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _ErrorEntry extends StatelessWidget {
  const _ErrorEntry({super.key, required this.sentence});

  final SentenceReview sentence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = sentence.error!;
    return _EntryCard(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${sentence.sentence.index + 1} 文目',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SentenceVerdictLabel(verdict: sentence.verdict),
            ErrorTypeTag(type: error.errorType),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          sentence.sentence.text,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '正しくは：${error.correction}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              size: 20,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '見ぬくコツ：${error.tip}',
                style: const TextStyle(height: 1.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FalseAlarmEntry extends StatelessWidget {
  const _FalseAlarmEntry({super.key, required this.sentence});

  final SentenceReview sentence;

  @override
  Widget build(BuildContext context) {
    return _EntryCard(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${sentence.sentence.index + 1} 文目',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            SentenceVerdictLabel(verdict: sentence.verdict),
          ],
        ),
        const SizedBox(height: 6),
        Text(sentence.sentence.text, style: const TextStyle(height: 1.5)),
      ],
    );
  }
}
