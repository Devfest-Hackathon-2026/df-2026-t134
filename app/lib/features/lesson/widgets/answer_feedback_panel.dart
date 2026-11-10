import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../lesson_state.dart';
import 'hallucination_feedback_view.dart';
import 'lesson_colors.dart';
import 'live_check_feedback_view.dart';

/// Feedback after 「チェック」: 正解！ / おしい！, the correct answer, the
/// explanation and 「つぎへ」.
class AnswerFeedbackPanel extends StatelessWidget {
  const AnswerFeedbackPanel({
    super.key,
    required this.checked,
    required this.step,
    required this.onNext,
  });

  final Checked checked;

  /// The step that was answered (a review step is not queued again).
  final LessonStep step;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final correct = checked.response.correct;
    final (color, background, icon, title) = correct
        ? (
            LessonColors.correct,
            LessonColors.correctBackground,
            Icons.check_circle_rounded,
            '正解！',
          )
        : (
            LessonColors.incorrect,
            LessonColors.incorrectBackground,
            Icons.error_rounded,
            'おしい！',
          );
    final explanation = _explanationOf(checked.response.result);
    return Container(
      key: Key(correct ? 'feedback-correct' : 'feedback-incorrect'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: color.withValues(alpha: .35))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (checked.correctAnswer case CorrectHallucination(
            :final review,
          )) ...[
            const SizedBox(height: 12),
            HallucinationFeedbackView(review: review),
          ] else if (checked.correctAnswer
              case final CorrectLiveCheck live) ...[
            const SizedBox(height: 12),
            LiveCheckFeedbackView(correct: live),
          ] else if (!correct) ...[
            const SizedBox(height: 8),
            Text(
              checked.response.result is StoryResult ? 'いちばんよい選択' : '正しい答え',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            _CorrectAnswerText(answer: checked.correctAnswer),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Text renders the `\n` in explanations as line breaks.
            Text(
              explanation,
              key: const Key('feedback-explanation'),
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
          ],
          if (!correct && !step.isReview) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.replay_rounded, size: 18),
                SizedBox(width: 4),
                Expanded(child: Text('この問題は、レッスンの最後にもう一度出るよ')),
              ],
            ),
          ],
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

  static String _explanationOf(AnswerResult result) => switch (result) {
    ChoiceResult(:final explanation) ||
    OrderResult(:final explanation) ||
    FillBlankResult(:final explanation) => explanation,
    HallucinationResult() => '', // tips are shown per error instead
    LiveCheckResult() => '',
    StoryResult(:final explanation) => explanation,
  };
}

class _CorrectAnswerText extends StatelessWidget {
  const _CorrectAnswerText({required this.answer});

  final CorrectAnswer answer;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 17, fontWeight: FontWeight.bold);
    return switch (answer) {
      CorrectText(:final text) => Text(
        text,
        key: const Key('feedback-correct-answer'),
        style: style,
      ),
      CorrectSequence(:final texts) => Column(
        key: const Key('feedback-correct-answer'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, text) in texts.indexed)
            Text('${i + 1}. $text', style: style),
        ],
      ),
      CorrectHallucination() => throw StateError(
        'A hallucination result is shown by HallucinationFeedbackView',
      ),
      CorrectLiveCheck() => throw StateError(
        'A live check result is shown by LiveCheckFeedbackView',
      ),
    };
  }
}
