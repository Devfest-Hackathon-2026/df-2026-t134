import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/motion.dart';

/// While the AI searches and answers (10–20 seconds): the learner's question
/// and a calm magnifier that slowly sweeps over three lines. With reduced
/// motion the picture stands still.
class LiveCheckGenerating extends ConsumerStatefulWidget {
  const LiveCheckGenerating({super.key, required this.prompt});

  final String prompt;

  @override
  ConsumerState<LiveCheckGenerating> createState() =>
      _LiveCheckGeneratingState();
}

class _LiveCheckGeneratingState extends ConsumerState<LiveCheckGenerating>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final still = reduceMotion(context, ref);
    if (still && _motion.isAnimating) {
      _motion.stop();
    } else if (!still && !_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'AI が Google 検索で調べて、答えを書いています',
      child: Container(
        key: const Key('live-check-generating'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Center(
                child: RepaintBoundary(
                  child: SizedBox(
                    width: 160,
                    height: 96,
                    child: CustomPaint(
                      painter: _SearchPainter(
                        _motion,
                        ink: scheme.outline,
                        accent: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'AI が調べて、答えを書いているよ…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Google 検索で調べてから答えるので、10〜20 秒くらいかかるよ。'
              'その間に、どこにまちがいがまぎれこみそうか考えてみよう',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              'あなたの質問',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.prompt,
              key: const Key('live-check-generating-prompt'),
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPainter extends CustomPainter {
  _SearchPainter(this.motion, {required this.ink, required this.accent})
    : super(repaint: motion);

  final Animation<double> motion;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink.withValues(alpha: .5)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final (i, width) in [.9, .7, .8].indexed) {
      final y = size.height * (.25 + i * .25);
      canvas.drawLine(
        Offset(size.width * .05, y),
        Offset(size.width * (.05 + width * .9), y),
        line,
      );
    }
    final t = Curves.easeInOut.transform(motion.value);
    final center = Offset(
      size.width * (.2 + t * .6),
      size.height * (.45 + math.sin(t * math.pi) * .1),
    );
    final lens = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final radius = size.height * .22;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = accent.withValues(alpha: .1),
    );
    canvas.drawCircle(center, radius, lens);
    canvas.drawLine(
      center + Offset(radius * .7, radius * .7),
      center + Offset(radius * 1.5, radius * 1.5),
      lens..strokeWidth = 6,
    );
  }

  @override
  bool shouldRepaint(_SearchPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.ink != ink ||
      oldDelegate.accent != accent;
}
