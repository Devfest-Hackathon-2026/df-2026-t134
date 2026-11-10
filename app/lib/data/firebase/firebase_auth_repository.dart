import 'package:firebase_auth/firebase_auth.dart';

import '../repositories.dart';

/// Error codes Firebase returns when the user closes or replaces the popup.
const _cancelledCodes = {
  'popup-closed-by-user',
  'cancelled-popup-request',
  'user-cancelled',
};

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(
    (user) => user == null
        ? null
        : AppUser(uid: user.uid, isAnonymous: user.isAnonymous),
  );

  @override
  Future<SignInOutcome> signInWithGoogle() async {
    try {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return SignInOutcome.signedIn;
    } on FirebaseAuthException catch (e) {
      if (_cancelledCodes.contains(e.code)) {
        return SignInOutcome.cancelled;
      }
      rethrow;
    }
  }

  @override
  Future<void> signInAnonymously() => _auth.signInAnonymously();

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> currentIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user for an authenticated API call');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase returned no ID token');
    }
    return token;
  }
}
