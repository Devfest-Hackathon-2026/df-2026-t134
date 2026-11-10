import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chapter_theme.dart';

final reducedMotionProvider = NotifierProvider<MotionPreference, bool>(
  MotionPreference.new,
);

class MotionPreference extends Notifier<bool> {
  @override
  bool build() => false;
  void setReduced(bool value) => state = value;
}

bool reduceMotion(BuildContext context, WidgetRef ref) =>
    MediaQuery.disableAnimationsOf(context) || ref.watch(reducedMotionProvider);

class MotionSettingsButton extends ConsumerWidget {
  const MotionSettingsButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduced = ref.watch(reducedMotionProvider);
    return IconButton(
      tooltip: reduced ? '動きを戻す' : '動きを控える',
      isSelected: reduced,
      icon: const Icon(Icons.motion_photos_on_outlined),
      selectedIcon: const Icon(Icons.motion_photos_off_outlined),
      onPressed: () =>
          ref.read(reducedMotionProvider.notifier).setReduced(!reduced),
    );
  }
}

/// Only this small, isolated canvas repaints; reading/answering surfaces stay still.
class AmbientMotif extends ConsumerStatefulWidget {
  const AmbientMotif({
    super.key,
    this.palette = ChapterPalette.common,
    this.size = 140,
    this.active = true,
  });
  final ChapterPalette palette;
  final double size;
  final bool active;
  @override
  ConsumerState<AmbientMotif> createState() => _AmbientMotifState();
}

class _AmbientMotifState extends ConsumerState<AmbientMotif>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate =
        !reduceMotion(context, ref) &&
        widget.active &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        _foreground &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) _motion.repeat();
    if (!animate && _motion.isAnimating) _motion.stop();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _MotifPainter(widget.palette, _motion)),
        ),
      ),
    );
  }
}

class _MotifPainter extends CustomPainter {
  _MotifPainter(this.palette, this.motion) : super(repaint: motion);
  final ChapterPalette palette;
  final Animation<double> motion;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * .36;
    final fill = Paint()..color = palette.wash;
    final line = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, r * 1.18, fill);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final wave = math.sin(motion.value * math.pi * 2);
    switch (palette.world) {
      case ChapterWorld.lab:
        canvas.rotate(-.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2, height: r),
          line,
        );
        canvas.rotate(1.1);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2, height: r),
          line,
        );
        canvas.drawCircle(
          Offset.zero,
          r * .24,
          Paint()..color = palette.accent,
        );
        canvas.drawCircle(
          Offset(
            math.cos(motion.value * math.pi * 2) * r,
            math.sin(motion.value * math.pi * 2) * r / 2,
          ),
          5,
          Paint()..color = palette.accent,
        );
      case ChapterWorld.adventure:
        final path = Path()
          ..moveTo(-r, r * .55)
          ..lineTo(-r * .3, -r * .55)
          ..lineTo(r * .15, r * .12)
          ..lineTo(r * .55, -r * .35)
          ..lineTo(r, r * .55);
        canvas.drawPath(path, line);
        canvas.drawCircle(
          Offset(r * .55, -r * .65 + wave * 3),
          7,
          Paint()..color = palette.accent,
        );
      case ChapterWorld.studio:
      case ChapterWorld.welcome:
        canvas.rotate(.10 + wave * .04);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(-r * .2, 0),
              width: r,
              height: r * 1.35,
            ),
            const Radius.circular(8),
          ),
          line,
        );
        canvas.drawCircle(
          Offset(r * .4, -r * .15 + wave * 3),
          r * .48,
          Paint()..color = palette.accent,
        );
        canvas.drawLine(
          Offset(-r * .45, r * .12),
          Offset(r * .1, r * .12),
          line,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MotifPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.motion != motion;
}
