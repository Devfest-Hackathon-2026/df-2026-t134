import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import '../../design/motion.dart';

/// Shown while the session is loading or could not be loaded.
class StartupPage extends ConsumerWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (session) {
              SessionFailed() => Column(
                key: const Key('startup-error'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'うまく読みこめませんでした',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '通信を確認して、もう一度試してね',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      ref.invalidate(authStateProvider);
                      ref.invalidate(profileProvider);
                    },
                    child: const Text('もう一度試す'),
                  ),
                ],
              ),
              _ => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmbientMotif(),
                  SizedBox(height: 16),
                  Text('学びの準備をしています', key: Key('startup-loading')),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}
