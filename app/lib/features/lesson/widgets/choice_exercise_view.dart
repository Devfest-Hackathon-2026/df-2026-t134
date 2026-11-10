import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../../../models/exercise.dart';
import 'lesson_colors.dart';

/// Q1: one tappable card per option.
class ChoiceExerciseView extends StatelessWidget {
  const ChoiceExerciseView({
    super.key,
    required this.exercise,
    required this.selectedOptionId,
    required this.result,
    required this.onSelect,
  });

  final ChoiceExercise exercise;
  final String? selectedOptionId;

  /// Set once the answer is checked; marks the right and the chosen option.
  final ChoiceResult? result;

  /// Null while the options cannot be changed (sending or checked).
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in exercise.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OptionCard(
              key: Key('choice-option-${option.id}'),
              text: option.text,
              mark: _markOf(option.id),
              onTap: switch (onSelect) {
                final select? => () => select(option.id),
                null => null,
              },
            ),
          ),
      ],
    );
  }

  _Mark _markOf(String optionId) {
    final isSelected = optionId == selectedOptionId;
    return switch (result) {
      null => isSelected ? _Mark.selected : _Mark.none,
      ChoiceResult(:final correctOptionId) when optionId == correctOptionId =>
        _Mark.correct,
      _ => isSelected ? _Mark.incorrect : _Mark.none,
    };
  }
}

enum _Mark { none, selected, correct, incorrect }

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    super.key,
    required this.text,
    required this.mark,
    required this.onTap,
  });

  final String text;
  final _Mark mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (borderColor, background, leading) = switch (mark) {
      _Mark.none => (
        scheme.outlineVariant,
        scheme.surface,
        Icon(Icons.radio_button_unchecked, color: scheme.outline),
      ),
      _Mark.selected => (
        scheme.primary,
        scheme.primaryContainer,
        Icon(Icons.radio_button_checked, color: scheme.primary),
      ),
      _Mark.correct => (
        LessonColors.correct,
        LessonColors.correctBackground,
        Icon(Icons.check_circle_rounded, color: LessonColors.correct),
      ),
      _Mark.incorrect => (
        LessonColors.incorrect,
        LessonColors.incorrectBackground,
        Icon(Icons.cancel_rounded, color: LessonColors.incorrect),
      ),
    };
    return Semantics(
      button: true,
      selected: mark == _Mark.selected,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: borderColor,
            width: mark == _Mark.none ? 1.5 : 3,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          style: const TextStyle(fontSize: 17, height: 1.5),
                        ),
                        if (mark == _Mark.correct)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: MarkLabel.correct(),
                          ),
                        if (mark == _Mark.incorrect)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: MarkLabel.incorrect(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
