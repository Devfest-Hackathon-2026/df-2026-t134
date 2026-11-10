import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../../../models/exercise.dart';
import 'lesson_colors.dart';

/// Q3 (fill in the blanks): the template with a numbered slot per blank and,
/// below it, the options of every blank as chips.
class FillBlankExerciseView extends StatelessWidget {
  const FillBlankExerciseView({
    super.key,
    required this.exercise,
    required this.selected,
    required this.result,
    required this.onChoose,
  });

  final FillBlankExercise exercise;

  /// Blank id → chosen option id.
  final Map<String, String> selected;

  /// Set once checked; marks each blank right or wrong.
  final FillBlankResult? result;

  /// `(blankId, optionId)`; null while the answer cannot change.
  final void Function(String blankId, String optionId)? onChoose;

  /// Up to 4 blanks (content schema).
  static const _numbers = ['①', '②', '③', '④'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numberOf = {
      for (final (i, blank) in exercise.blanks.indexed) blank.id: _numbers[i],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('fill-blank-template'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 18, height: 2),
              children: [
                for (final part in exercise.parts)
                  switch (part) {
                    TemplateText(:final text) => TextSpan(text: text),
                    TemplateSlot(:final blank) => WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _Slot(
                        key: Key('blank-slot-${blank.id}'),
                        number: numberOf[blank.id]!,
                        text: _chosenText(blank),
                        isCorrect: _isCorrect(blank),
                      ),
                    ),
                  },
              ],
            ),
          ),
        ),
        for (final blank in exercise.blanks) ...[
          const SizedBox(height: 16),
          Text(
            '空らん${numberOf[blank.id]} に入ることば',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in blank.options)
                ChoiceChip(
                  key: Key('blank-${blank.id}-option-${option.id}'),
                  label: Text(option.text),
                  labelStyle: const TextStyle(fontSize: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  selected: selected[blank.id] == option.id,
                  onSelected: switch (onChoose) {
                    final choose? => (_) => choose(blank.id, option.id),
                    null => null,
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  String? _chosenText(Blank blank) {
    final optionId = selected[blank.id];
    return blank.options.where((o) => o.id == optionId).firstOrNull?.text;
  }

  bool? _isCorrect(Blank blank) => switch (result) {
    FillBlankResult(:final correctOptions) =>
      correctOptions[blank.id] == selected[blank.id],
    null => null,
  };
}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.number,
    required this.text,
    required this.isCorrect,
  });

  final String number;

  /// Null while the blank is empty.
  final String? text;

  /// Null until the answer is checked.
  final bool? isCorrect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (border, background, icon) = switch (isCorrect) {
      true => (
        LessonColors.correct,
        LessonColors.correctBackground,
        Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: LessonColors.correct,
          semanticLabel: 'せいかい',
        ),
      ),
      false => (
        LessonColors.incorrect,
        LessonColors.incorrectBackground,
        Icon(
          Icons.cancel_rounded,
          size: 18,
          color: LessonColors.incorrect,
          semanticLabel: 'ちがうよ',
        ),
      ),
      null => (scheme.primary, scheme.surface, null),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$number ${text ?? '？？？'}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: text == null ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
          if (icon != null) ...[const SizedBox(width: 4), icon],
        ],
      ),
    );
  }
}
