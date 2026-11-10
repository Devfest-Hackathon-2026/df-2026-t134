import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/chapter_theme.dart';
import '../../../design/motion.dart';
import '../lesson_state.dart';
import 'lesson_colors.dart';

/// Server-owned progress, displayed without calculating or awarding local XP.
class LessonResultView extends ConsumerWidget {
  const LessonResultView({
    super.key,
    required this.finished,
    required this.onBackToPath,
  });
  final LessonFinished finished;
  final VoidCallback onBackToPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = finished.progress;
    final (icon, title) = switch (finished.outcome) {
      LessonCompleted() => (Icons.emoji_events_rounded, 'レッスンクリア！'),
      LessonNotCompleted() => (Icons.flag_rounded, 'おつかれさま！'),
    };
    final quiet = reduceMotion(context, ref);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: quiet ? 1 : .85, end: 1),
            duration: quiet ? Duration.zero : const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(icon, size: 52, color: theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          key: const Key('result-title'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          finished.lesson.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (finished.outcome is LessonNotCompleted) ...[
          const SizedBox(height: 24),
          Container(
            key: const Key('result-not-completed'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'まだ答えていない問題があるので、クリアボーナスはお預けだよ。ぜんぶの問題に答えるとクリアになるよ',
            ),
          ),
        ],
        const SizedBox(height: 32),
        Container(
          key: const Key('result-xp-gained'),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('もらった XP', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                '+${finished.xpGained} XP',
                style: TextStyle(
                  fontSize: 40,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (progress != null) ...[
          _StatTile(
            key: const Key('result-xp-total'),
            icon: Icons.stars_rounded,
            color: theme.colorScheme.primary,
            label: 'ごうけい XP',
            value: '${progress.xp} XP',
          ),
          _StatTile(
            key: const Key('result-streak'),
            icon: Icons.local_fire_department_rounded,
            color: theme.colorScheme.primary,
            label: '連続学習',
            value: '${progress.streakDays} 日',
          ),
        ],
        _StatTile(
          key: const Key('result-correct'),
          icon: Icons.check_circle_rounded,
          color: LessonColors.correct,
          label: '1 回目で正解',
          value:
              '${finished.tally.firstTryCorrect} / ${finished.questionCount} もん',
        ),
        const SizedBox(height: 32),
        FilledButton(
          key: const Key('lesson-back-to-path'),
          onPressed: onBackToPath,
          child: const Text('学習パスにもどる'),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE6D8CD))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 16),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 8,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: ChapterPalette.muted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
