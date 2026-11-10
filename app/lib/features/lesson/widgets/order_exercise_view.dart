import 'package:flutter/material.dart';

import '../../../models/answer.dart';
import '../../../models/exercise.dart';
import '../shuffle.dart';
import 'lesson_colors.dart';

/// Q3 (order): the learner taps the shuffled items in order. Tapping a placed
/// item takes it back; 「ひとつもどす」 takes back the last one.
class OrderExerciseView extends StatelessWidget {
  const OrderExerciseView({
    super.key,
    required this.exercise,
    required this.pickedIds,
    required this.result,
    required this.onAdd,
    required this.onRemove,
    required this.onUndo,
  });

  final OrderExercise exercise;

  /// Item ids in the order the learner placed them.
  final List<String> pickedIds;

  /// Set once checked; marks each placed position right or wrong.
  final OrderResult? result;

  /// The callbacks are null while the answer cannot change.
  final ValueChanged<String>? onAdd;
  final ValueChanged<String>? onRemove;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final byId = {for (final item in exercise.items) item.id: item};
    final remaining = [
      for (final item in shuffledItems(exercise))
        if (!pickedIds.contains(item.id)) item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            Text(
              'あなたの順番',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              key: const Key('order-undo'),
              onPressed: pickedIds.isEmpty ? null : onUndo,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('ひとつもどす'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pickedIds.isEmpty)
          _EmptyAnswer()
        else
          for (final (position, id) in pickedIds.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlacedItem(
                key: Key('order-picked-$id'),
                number: position + 1,
                text: byId[id]!.text,
                isCorrect: switch (result) {
                  OrderResult(:final correctOrder) =>
                    position < correctOrder.length &&
                        correctOrder[position] == id,
                  null => null,
                },
                onTap: switch (onRemove) {
                  final remove? => () => remove(id),
                  null => null,
                },
              ),
            ),
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('タップしてならべよう', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final item in remaining)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PoolItem(
                key: Key('order-item-${item.id}'),
                text: item.text,
                onTap: switch (onAdd) {
                  final add? => () => add(item.id),
                  null => null,
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _EmptyAnswer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: Text(
        '下のカードを、1 番目から順番にタップしてね',
        textAlign: TextAlign.center,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _PlacedItem extends StatelessWidget {
  const _PlacedItem({
    super.key,
    required this.number,
    required this.text,
    required this.isCorrect,
    required this.onTap,
  });

  final int number;
  final String text;

  /// Null until the answer is checked.
  final bool? isCorrect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (border, background) = switch (isCorrect) {
      true => (LessonColors.correct, LessonColors.correctBackground),
      false => (LessonColors.incorrect, LessonColors.incorrectBackground),
      null => (scheme.primary, scheme.primaryContainer),
    };
    return Semantics(
      button: onTap != null,
      label: '$number 番目',
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 2.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: border,
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text, style: const TextStyle(fontSize: 16)),
                        if (isCorrect == true) const MarkLabel.correct(),
                        if (isCorrect == false) const MarkLabel.incorrect(),
                      ],
                    ),
                  ),
                  switch (isCorrect) {
                    true || false => const SizedBox.shrink(),
                    null when onTap != null => Icon(
                      Icons.close_rounded,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: 'とりけす',
                    ),
                    null => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PoolItem extends StatelessWidget {
  const _PoolItem({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: scheme.surface,
        elevation: onTap == null ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text, style: const TextStyle(fontSize: 16)),
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
