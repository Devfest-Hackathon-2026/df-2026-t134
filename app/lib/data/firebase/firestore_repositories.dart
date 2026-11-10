import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/content.dart';
import '../../models/exercise.dart';
import '../../models/progress.dart';
import '../../models/user_profile.dart';
import '../repositories.dart';
import 'firestore_json.dart';

// Collection names are part of the contract (api/app/schemas/firestore.py).
const _users = 'users';
const _progress = 'progress';
const _units = 'units';
const _lessons = 'lessons';
const _exercises = 'exercises';

/// Snapshots confirmed by the server only:
/// - a local snapshot of a pending write still has `createdAt` (a server
///   timestamp) unresolved, and
/// - a cache-only "does not exist" must not send an existing user to the
///   onboarding screen.
Stream<DocumentSnapshot<Map<String, dynamic>>> _confirmedSnapshots(
  DocumentReference<Map<String, dynamic>> ref,
) => ref
    .snapshots(includeMetadataChanges: true)
    .where(
      (snapshot) =>
          !snapshot.metadata.hasPendingWrites && !snapshot.metadata.isFromCache,
    );

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserProfile?> watchProfile(String uid) => _confirmedSnapshots(
    _db.collection(_users).doc(uid),
  ).map((doc) => doc.exists ? UserProfile.fromJson(documentJson(doc)) : null);

  @override
  Future<void> createProfile(String uid, ProfileDraft draft) {
    // firebase/firestore.rules accepts exactly these three fields.
    return _db.collection(_users).doc(uid).set({
      'displayName': draft.displayName,
      'grade': draft.grade.code,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

class FirestoreProgressRepository implements ProgressRepository {
  FirestoreProgressRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<Progress> watchProgress(String uid) =>
      _confirmedSnapshots(_db.collection(_progress).doc(uid)).map(
        (doc) =>
            doc.exists ? Progress.fromJson(documentJson(doc)) : Progress.empty,
      );
}

class FirestoreContentRepository implements ContentRepository {
  FirestoreContentRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<List<Unit>> fetchUnits() async {
    final snapshot = await _db.collection(_units).get();
    return [
      for (final doc in snapshot.docs) Unit.fromJson(contentDocumentJson(doc)),
    ];
  }

  @override
  Future<List<Lesson>> fetchLessons() async {
    final snapshot = await _db.collection(_lessons).get();
    return [
      for (final doc in snapshot.docs)
        Lesson.fromJson(contentDocumentJson(doc)),
    ];
  }

  @override
  Future<Lesson?> fetchLesson(String lessonId) async {
    final doc = await _db.collection(_lessons).doc(lessonId).get();
    return doc.exists ? Lesson.fromJson(contentDocumentJson(doc)) : null;
  }

  @override
  Future<List<Exercise>> fetchExercises(List<String> exerciseIds) {
    final exercises = _db.collection(_exercises);
    // Future.wait keeps the order of exerciseIds. A missing document makes
    // contentDocumentJson throw FormatException.
    return Future.wait([
      for (final id in exerciseIds)
        exercises
            .doc(id)
            .get()
            .then((doc) => Exercise.fromJson(contentDocumentJson(doc))),
    ]);
  }
}
