/// Interfaces in front of Firebase. Widgets and providers only see these, so
/// tests can swap in fakes (implementations live in `firebase/`).
library;

import '../models/content.dart';
import '../models/exercise.dart';
import '../models/progress.dart';
import '../models/user_profile.dart';

/// The signed-in Firebase user, reduced to what the app needs.
class AppUser {
  const AppUser({required this.uid, required this.isAnonymous});

  final String uid;

  /// Signed in with "ゲストではじめる".
  final bool isAnonymous;
}

/// Result of an interactive sign-in. Closing the popup is a normal outcome,
/// other failures are thrown.
enum SignInOutcome { signedIn, cancelled }

abstract interface class AuthRepository {
  /// Emits the current user right away, then on every sign-in / sign-out.
  Stream<AppUser?> authStateChanges();

  Future<SignInOutcome> signInWithGoogle();

  Future<void> signInAnonymously();

  Future<void> signOut();

  /// Firebase ID token of the current user, for `Authorization: Bearer`.
  /// Throws [StateError] when nobody is signed in.
  Future<String> currentIdToken();
}

abstract interface class ProfileRepository {
  /// `users/{uid}`; emits null while the document does not exist.
  Stream<UserProfile?> watchProfile(String uid);

  /// Creates `users/{uid}` with the server time as `createdAt`.
  Future<void> createProfile(String uid, ProfileDraft draft);
}

abstract interface class ContentRepository {
  Future<List<Unit>> fetchUnits();

  Future<List<Lesson>> fetchLessons();

  /// `lessons/{lessonId}`; null when the lesson does not exist.
  Future<Lesson?> fetchLesson(String lessonId);

  /// `exercises/{id}` for every id, in the given order. A missing exercise is
  /// broken content and throws [FormatException].
  Future<List<Exercise>> fetchExercises(List<String> exerciseIds);
}

abstract interface class ProgressRepository {
  /// `progress/{uid}`; emits [Progress.empty] while the document does not exist.
  Stream<Progress> watchProgress(String uid);
}
