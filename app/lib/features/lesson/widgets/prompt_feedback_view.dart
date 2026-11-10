import 'package:flutter/material.dart';

import '../../../models/prompt_evaluation.dart';
import 'lesson_colors.dart';

/// Feedback after a prompt was graded: いいね！ / もう少し！, the total, one
/// meter per rubric axis, the good point, what to improve, a hint and
/// 「つぎへ」.
///
/// Audio seam (PR-15): the feedback can be read aloud by sending
/// `evaluation.attemptId` to `/v1/tts`; a play button belongs next to the
/// header. The texts stay on screen, so the feedback works with sound off.
class PromptFeedbackView extends StatelessWidget {
  const PromptFeedbackView({
    super.key,
    required this.evaluation,
    required this.onNext,
  });

  final PromptEvaluated evaluation;
  final VoidCallback onNext;

  static String axisLabel(RubricAxis axis) => switch (axis) {
    RubricAxis.purpose => '目的',
    RubricAxis.context => '前提・文脈',
    RubricAxis.constraints => '条件・制約',
    RubricAxis.format => '出力形式',
    RubricAxis.safety => '安全',
  };

  @override
  Widget build(BuildContext context) {
    final passed = evaluation.passed;
    final (color, background, icon, title) = passed
        ? (
            LessonColors.correct,
            LessonColors.correctBackground,
            Icons.thumb_up_alt_rounded,
            'いいね！',
          )
        : (
            LessonColors.incorrect,
            LessonColors.incorrectBackground,
            Icons.trending_up_rounded,
            'もう少し！',
          );
    final xpGained = evaluation.progress.xpGained;
    return Container(
      key: Key(passed ? 'prompt-feedback-good' : 'prompt-feedback-more'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: color.withValues(alpha: .35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              Text(
                '${evaluation.total} / ${PromptEvaluated.maxTotal} 点',
                key: const Key('prompt-total'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (xpGained > 0)
                Text(
                  '+$xpGained XP',
                  key: const Key('prompt-xp'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final axis in RubricAxis.values)
            _AxisMeter(
              key: Key('prompt-axis-${axis.name}'),
              label: axisLabel(axis),
              score: evaluation.scores.of(axis),
              color: color,
            ),
          if (evaluation.goodPoint.isNotEmpty)
            _Section(
              key: const Key('prompt-good-point'),
              icon: Icons.star_rounded,
              title: 'よかったところ',
              lines: [evaluation.goodPoint],
            ),
          _Section(
            key: const Key('prompt-improvements'),
            icon: Icons.build_circle_outlined,
            title: 'もっとよくするには',
            lines: evaluation.improvements,
          ),
          if (evaluation.hint.isNotEmpty)
            _Section(
              key: const Key('prompt-hint'),
              icon: Icons.lightbulb_outline_rounded,
              title: 'ヒント',
              lines: [evaluation.hint],
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('lesson-next'),
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: onNext,
            child: const Text('つぎへ'),
          ),
        ],
      ),
    );
  }
}

/// A rubric axis as "label  n / 2" over a two-segment meter.
class _AxisMeter extends StatelessWidget {
  const _AxisMeter({
    super.key,
    required this.label,
    required this.score,
    required this.color,
  });

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const max = RubricScores.maxPerAxis;
    final empty = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: '$label $max 点中 $score 点',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('$score / $max'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < max; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: i < score ? color : empty,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Text(
              lines.length > 1 ? '・$line' : line,
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
        ],
      ),
    );
  }
}
