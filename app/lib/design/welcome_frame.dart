import 'package:flutter/material.dart';

import 'chapter_theme.dart';
import 'motion.dart';

/// A shared, scroll-safe entrance to the learning experience.
class WelcomeFrame extends StatelessWidget {
  const WelcomeFrame({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'ailearn',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.8),
      ),
      actions: [
        ...actions,
        const MotionSettingsButton(),
        const SizedBox(width: 12),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final introduction = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AmbientMotif(size: wide ? 200 : 80),
              SizedBox(height: wide ? 32 : 8),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.7,
                  color: ChapterPalette.muted,
                ),
              ),
              if (wide) ...[
                const SizedBox(height: 40),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('知る')),
                    Chip(label: Text('つくる')),
                    Chip(label: Text('確かめる')),
                  ],
                ),
              ],
            ],
          );
          final panel = Container(
            padding: EdgeInsets.all(wide ? 32 : 20),
            decoration: BoxDecoration(
              color: ChapterPalette.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE6D8CD)),
            ),
            child: child,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 20,
              vertical: wide ? 48 : 16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: introduction),
                          const SizedBox(width: 64),
                          Expanded(child: panel),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          introduction,
                          const SizedBox(height: 24),
                          panel,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
