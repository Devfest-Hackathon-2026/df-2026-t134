import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pre-generated media (story pictures under `images/`, voices under
/// `audio/`) in Cloud Storage, readable by signed-in learners.
abstract interface class MediaRepository {
  /// A URL the browser can load [storagePath] from. Throws when the file is
  /// missing or cannot be read.
  Future<Uri> downloadUrl(String storagePath);
}

/// Overridden in main() with Cloud Storage. Without it (tests, previews) the
/// story shows its picture placeholders and no voice buttons.
final mediaRepositoryProvider = Provider<MediaRepository?>((ref) => null);

/// The URL of a stored file, or null without a [MediaRepository]. Kept for
/// the session, so going back and forth between scenes does not refetch.
final mediaUrlProvider = FutureProvider.family<Uri?, String>((ref, path) {
  final media = ref.watch(mediaRepositoryProvider);
  return media?.downloadUrl(path);
}, retry: (retryCount, error) => null);
