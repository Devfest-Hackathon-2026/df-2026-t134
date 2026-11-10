import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../models/user_profile.dart';

/// Who is using the app, derived from the auth state and `users/{uid}`.
/// The router redirects on this and screens read the user from it.
sealed class Session {
  const Session();
}

final class SessionLoading extends Session {
  const SessionLoading();
}

final class SessionFailed extends Session {
  const SessionFailed(this.error);

  final Object error;
}

final class SignedOut extends Session {
  const SignedOut();
}

/// Signed in, but `users/{uid}` does not exist yet.
final class NeedsProfile extends Session {
  const NeedsProfile(this.user);

  final AppUser user;
}

final class Ready extends Session {
  const Ready(this.user, this.profile);

  final AppUser user;
  final UserProfile profile;
}

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
  retry: noRetry,
);

/// Keyed by uid so a new user never sees the previous user's profile.
final profileProvider = StreamProvider.autoDispose.family<UserProfile?, String>(
  (ref, uid) => ref.watch(profileRepositoryProvider).watchProfile(uid),
  retry: noRetry,
);

final sessionProvider = Provider<Session>((ref) {
  switch (ref.watch(authStateProvider)) {
    case AsyncError(:final error):
      return SessionFailed(error);
    case AsyncData(value: null):
      return const SignedOut();
    case AsyncData(value: final AppUser user):
      return switch (ref.watch(profileProvider(user.uid))) {
        AsyncError(:final error) => SessionFailed(error),
        AsyncData(value: null) => NeedsProfile(user),
        AsyncData(value: final UserProfile profile) => Ready(user, profile),
        _ => const SessionLoading(),
      };
    default:
      return const SessionLoading();
  }
});
