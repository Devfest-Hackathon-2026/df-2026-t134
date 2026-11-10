import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import '../design/chapter_theme.dart';

class AilearnApp extends ConsumerWidget {
  const AilearnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ailearn',
      theme: ailearnTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
