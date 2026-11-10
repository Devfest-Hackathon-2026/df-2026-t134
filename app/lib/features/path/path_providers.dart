import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/providers.dart';
import '../../models/content.dart';
import '../../models/progress.dart';
import 'learning_path.dart';

/// Published units; content changes only on deploy, so read once.
final unitsProvider = FutureProvider<List<Unit>>(
  (ref) => ref.watch(contentRepositoryProvider).fetchUnits(),
  retry: noRetry,
);

final lessonsProvider = FutureProvider<List<Lesson>>(
  (ref) => ref.watch(contentRepositoryProvider).fetchLessons(),
  retry: noRetry,
);

/// Live, so a lesson completed in PR-07's player unlocks the next one here.
final progressProvider = StreamProvider.autoDispose.family<Progress, String>(
  (ref, uid) => ref.watch(progressRepositoryProvider).watchProgress(uid),
  retry: noRetry,
);

/// The learning path of [uid]. Inconsistent content becomes an [AsyncError]
/// so the screen shows an error instead of a wrong path.
final learningPathProvider = Provider.autoDispose
    .family<AsyncValue<LearningPath>, String>((ref, uid) {
      final units = ref.watch(unitsProvider);
      final lessons = ref.watch(lessonsProvider);
      final progress = ref.watch(progressProvider(uid));
      for (final value in [units, lessons, progress]) {
        if (value case AsyncError(:final error, :final stackTrace)) {
          return AsyncError(error, stackTrace);
        }
      }
      if ((units, lessons, progress) case (
        AsyncData(value: final u),
        AsyncData(value: final l),
        AsyncData(value: final p),
      )) {
        try {
          return AsyncData(
            buildLearningPath(units: u, lessons: l, progress: p),
          );
        } on FormatException catch (error, stackTrace) {
          return AsyncError(error, stackTrace);
        }
      }
      return const AsyncLoading();
    });

/// Reloads everything the learning path depends on.
void refreshLearningPath(WidgetRef ref) {
  ref
    ..invalidate(unitsProvider)
    ..invalidate(lessonsProvider)
    ..invalidate(progressProvider);
}
