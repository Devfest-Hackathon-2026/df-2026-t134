import 'package:flutter/material.dart';

/// Colors for right / wrong marks. Always paired with an icon and a text so
/// the meaning does not depend on color alone.
abstract final class LessonColors {
  static const correct = Color(0xFF496438);
  static const correctBackground = Color(0xFFF0F1E5);
  static const incorrect = Color(0xFFAB452E);
  static const incorrectBackground = Color(0xFFFCEBE1);
}

/// Icon + short label shown next to a marked option.
class MarkLabel extends StatelessWidget {
  const MarkLabel.correct({super.key})
    : _icon = Icons.check_circle_rounded,
      _text = 'せいかい',
      _isCorrect = true;

  const MarkLabel.incorrect({super.key})
    : _icon = Icons.cancel_rounded,
      _text = 'ちがうよ',
      _isCorrect = false;

  final IconData _icon;
  final String _text;
  final bool _isCorrect;

  @override
  Widget build(BuildContext context) {
    final color = _isCorrect ? LessonColors.correct : LessonColors.incorrect;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, color: color, size: 22),
        const SizedBox(width: 4),
        Text(
          _text,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
