import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../hallucination_review.dart';
import 'lesson_colors.dart';

/// Short Japanese name of an error type, for learners.
String hallucinationErrorLabel(HallucinationErrorType type) => switch (type) {
  HallucinationErrorType.number => '数字',
  HallucinationErrorType.date => '日付',
  HallucinationErrorType.name => '名前',
  HallucinationErrorType.fakeSource => 'ないはずの出典',
  HallucinationErrorType.causality => '原因と結果',
  HallucinationErrorType.fact => '事実',
};

/// Icon + text for a sentence verdict, so the meaning never depends on
/// color alone.
class SentenceVerdictLabel extends StatelessWidget {
  const SentenceVerdictLabel({super.key, required this.verdict});

  final SentenceVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (verdict) {
      SentenceVerdict.found => (
        Icons.check_circle_rounded,
        '見つけた！',
        LessonColors.correct,
      ),
      SentenceVerdict.missed => (
        Icons.visibility_off_rounded,
        '見のがし',
        LessonColors.incorrect,
      ),
      SentenceVerdict.falseAlarm => (
        Icons.cancel_rounded,
        '正しい文だったよ',
        LessonColors.incorrect,
      ),
      SentenceVerdict.untouched => (
        Icons.check_rounded,
        '正しい文',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// The kind of mistake, e.g. 「数字」, as a small outlined tag.
class ErrorTypeTag extends StatelessWidget {
  const ErrorTypeTag({super.key, required this.type});

  final HallucinationErrorType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(
        'まちがいの種類：${hallucinationErrorLabel(type)}',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
