import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/health_status.dart';

/// Retries are triggered by the user, not automatically.
final healthProvider = FutureProvider<HealthStatus>(
  (ref) => ref.watch(apiClientProvider).fetchHealth(),
  retry: noRetry,
);

/// Small dot showing whether the learning API answers `GET /v1/health`.
/// Tapping it checks again.
class ApiStatusIndicator extends ConsumerWidget {
  const ApiStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, message) = switch (ref.watch(healthProvider)) {
      AsyncData(:final value) => (
        Colors.green,
        'API に接続しました（${value.env} / v${value.version}）',
      ),
      AsyncError() => (Colors.red, 'API に接続できませんでした（タップで再確認）'),
      _ => (Colors.grey, 'API を確認しています'),
    };
    return IconButton(
      key: const Key('api-status'),
      tooltip: message,
      onPressed: () => ref.invalidate(healthProvider),
      icon: Icon(Icons.circle, size: 12, color: color, semanticLabel: message),
    );
  }
}
