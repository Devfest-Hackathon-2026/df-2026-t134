import 'package:flutter/material.dart';

import '../../../models/answer_mark.dart';
import '../../../models/exercise.dart';
import '../hallucination_review.dart';
import 'answer_passage.dart';

/// Read and verify a complete AI answer, without revealing whether it has errors.
class HallucinationExerciseView extends StatelessWidget {
  const HallucinationExerciseView({
    super.key,
    required this.exercise,
    required this.selectedIndexes,
    required this.review,
    this.onToggle,
    this.marks = const [],
    this.confirmedNoErrors = false,
    this.onMark,
    this.onRemove,
    this.onNoErrors,
  });
  final HallucinationExercise exercise;
  final Set<int> selectedIndexes;
  final HallucinationReview? review;
  final ValueChanged<int>? onToggle;
  final List<AnswerMark> marks;
  final bool confirmedNoErrors;
  final ValueChanged<AnswerMark>? onMark;
  final ValueChanged<AnswerMark>? onRemove;
  final VoidCallback? onNoErrors;
  @override
  Widget build(BuildContext context) {
    final editable = review == null && (onMark != null || onToggle != null);
    final shownMarks = marks.isNotEmpty
        ? marks
        : [
            for (final i in selectedIndexes)
              sentenceMark(exercise.sentences, i),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '質問に対して正しい答えが返ってきているか確かめよう。',
          key: const Key('hallucination-instructions'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(exercise.topic, key: const Key('hallucination-topic')),
        const SizedBox(height: 12),
        AnswerPassage(
          key: ValueKey(exercise.id),
          prefix: 'hallucination',
          sentences: exercise.sentences,
          marks: shownMarks,
          confirmedNoErrors: confirmedNoErrors,
          review: review,
          onMark: !editable
              ? null
              : onMark ??
                    (mark) {
                      for (final i in markedIndexes(exercise.sentences, [
                        mark,
                      ])) {
                        if (!selectedIndexes.contains(i)) onToggle!(i);
                      }
                    },
          onRemove: !editable
              ? null
              : onRemove ??
                    (mark) {
                      for (final i in markedIndexes(exercise.sentences, [
                        mark,
                      ])) {
                        if (selectedIndexes.contains(i)) onToggle?.call(i);
                      }
                    },
          onNoErrors: editable ? onNoErrors : null,
        ),
      ],
    );
  }
}
