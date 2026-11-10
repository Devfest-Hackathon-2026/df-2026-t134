import 'package:ailearn/design/motion.dart';

import 'dart:async';

import 'package:ailearn/app/app.dart';
import 'package:ailearn/core/api_client.dart';
import 'package:ailearn/core/providers.dart';
import 'package:ailearn/data/providers.dart';
import 'package:ailearn/data/repositories.dart';
import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:ailearn/models/progress.dart';
import 'package:ailearn/models/user_profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_api.dart';

/// In-memory auth. Sign-ins emit synchronously like a real auth listener.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? initialUser}) : _user = initialUser;

  AppUser? _user;
  final _changes = StreamController<AppUser?>.broadcast();

  SignInOutcome googleOutcome = SignInOutcome.signedIn;
  Object? signInError;
  int googleCalls = 0;
  int anonymousCalls = 0;

  AppUser? get user => _user;

  void setUser(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<SignInOutcome> signInWithGoogle() async {
    googleCalls++;
    if (signInError case final error?) {
      throw error;
    }
    if (googleOutcome == SignInOutcome.signedIn) {
      setUser(const AppUser(uid: 'google-user', isAnonymous: false));
    }
    return googleOutcome;
  }

  @override
  Future<void> signInAnonymously() async {
    anonymousCalls++;
    if (signInError case final error?) {
      throw error;
    }
    setUser(const AppUser(uid: 'guest-user', isAnonymous: true));
  }

  @override
  Future<void> signOut() async => setUser(null);

  @override
  Future<String> currentIdToken() async {
    if (_user == null) {
      throw StateError('signed out');
    }
    return 'token-of-${_user!.uid}';
  }
}

/// `users/{uid}` documents kept in memory.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([Map<String, UserProfile>? profiles])
    : _profiles = {...?profiles};

  final Map<String, UserProfile> _profiles;
  final _changes = StreamController<String>.broadcast();
  final created = <(String, ProfileDraft)>[];
  Object? createError;

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield _profiles[uid];
    yield* _changes.stream.where((id) => id == uid).map((id) => _profiles[id]);
  }

  @override
  Future<void> createProfile(String uid, ProfileDraft draft) async {
    if (createError case final error?) {
      throw error;
    }
    created.add((uid, draft));
    _profiles[uid] = UserProfile(
      displayName: draft.displayName,
      grade: draft.grade,
      createdAt: DateTime.utc(2026, 11, 9),
    );
    _changes.add(uid);
  }
}

class FakeContentRepository implements ContentRepository {
  FakeContentRepository({
    this.units = const [],
    this.lessons = const [],
    List<Exercise> exercises = const [],
  }) : exercises = {for (final e in exercises) e.id: e};

  List<Unit> units;
  List<Lesson> lessons;
  Map<String, Exercise> exercises;
  Object? error;

  /// Thrown by [fetchExercises] while set.
  Object? exercisesError;

  @override
  Future<List<Unit>> fetchUnits() async {
    if (error case final e?) {
      throw e;
    }
    return units;
  }

  @override
  Future<List<Lesson>> fetchLessons() async => lessons;

  @override
  Future<Lesson?> fetchLesson(String lessonId) async =>
      lessons.where((l) => l.id == lessonId).firstOrNull;

  @override
  Future<List<Exercise>> fetchExercises(List<String> exerciseIds) async {
    if (exercisesError case final e?) {
      throw e;
    }
    return [
      for (final id in exerciseIds)
        exercises[id] ?? (throw FormatException('Missing exercise $id')),
    ];
  }
}

class FakeProgressRepository implements ProgressRepository {
  FakeProgressRepository([Map<String, Progress>? progress])
    : _progress = {...?progress};

  final Map<String, Progress> _progress;

  @override
  Stream<Progress> watchProgress(String uid) =>
      Stream.value(_progress[uid] ?? Progress.empty);
}

Unit unit(String id, int order, {String? title}) => Unit(
  id: id,
  order: order,
  title: title ?? 'ユニット $id',
  description: '$id の説明',
  level: 1,
);

Lesson lesson(String id, String unitId, int order, {String? title}) => Lesson(
  id: id,
  unitId: unitId,
  order: order,
  title: title ?? 'レッスン $id',
  exerciseIds: ['$id-q1'],
);

/// A two-option choice exercise (the fake API needs a matching answer key).
ChoiceExercise choiceExercise(String id, String lessonId) => ChoiceExercise(
  id: id,
  lessonId: lessonId,
  question: '$id の問題',
  options: const [
    Option(id: 'a', text: 'こたえ A'),
    Option(id: 'b', text: 'こたえ B'),
  ],
);

Progress progressWith(Set<String> completed, {int xp = 0}) => Progress(
  xp: xp,
  streakDays: 0,
  lastStudiedOn: null,
  freezeTickets: 0,
  completedLessonIds: completed,
);

final sampleProfile = UserProfile(
  displayName: 'ひかり',
  grade: Grade.j2,
  createdAt: DateTime.utc(2026, 11, 1),
);

/// The whole app (router included) wired to fakes. Without [api] the API
/// only answers the health check.
Widget buildTestApp({
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeContentRepository? content,
  FakeProgressRepository? progress,
  FakeLearningApi? api,
  bool reducedMotion = true,
}) {
  final apiClient =
      api?.client(idToken: auth.currentIdToken) ??
      ApiClient(
        baseUrl: Uri.parse('http://localhost:8000'),
        httpClient: MockClient(
          (_) async => http.Response(
            '{"status":"ok","version":"0.1.0","env":"test"}',
            200,
          ),
        ),
        idToken: auth.currentIdToken,
        appCheckToken: noAppCheckToken,
      );
  return ProviderScope(
    overrides: [
      reducedMotionProvider.overrideWith(
        () => _TestMotionPreference(reducedMotion),
      ),
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(
        profiles ?? FakeProfileRepository(),
      ),
      contentRepositoryProvider.overrideWithValue(
        content ?? FakeContentRepository(),
      ),
      progressRepositoryProvider.overrideWithValue(
        progress ?? FakeProgressRepository(),
      ),
      apiClientProvider.overrideWithValue(apiClient),
    ],
    child: const AilearnApp(),
  );
}

class _TestMotionPreference extends MotionPreference {
  _TestMotionPreference(this.reduced);
  final bool reduced;
  @override
  bool build() => reduced;
}
