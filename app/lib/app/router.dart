import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/session.dart';
import '../features/lesson/lesson_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/path/path_page.dart';
import '../features/startup/startup_page.dart';
import 'routes.dart';

/// Pages that only make sense before the session is [Ready].
const _gatePaths = {Routes.startup, Routes.login, Routes.onboarding};

/// Where to send the user for [session] when they are at [location]
/// (null = stay).
///
/// While the session is loading the original location is kept in `from` so a
/// reload of `/lessons/x` comes back to it.
String? redirectFor(Session session, Uri location) {
  final path = location.path;
  switch (session) {
    case SessionLoading() || SessionFailed():
      if (path == Routes.startup) {
        return null;
      }
      return Uri(
        path: Routes.startup,
        queryParameters: _gatePaths.contains(path)
            ? null
            : {'from': location.toString()},
      ).toString();
    case SignedOut():
      return path == Routes.login ? null : Routes.login;
    case NeedsProfile():
      return path == Routes.onboarding ? null : Routes.onboarding;
    case Ready():
      if (!_gatePaths.contains(path)) {
        return null;
      }
      return _safeReturnLocation(location.queryParameters['from']) ??
          Routes.path;
  }
}

/// Only in-app paths, never another origin (`//host`) or a gate page.
String? _safeReturnLocation(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  return _gatePaths.contains(Uri.parse(from).path) ? null : from;
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<Session>(const SessionLoading());
  ref.listen(
    sessionProvider,
    (_, next) => session.value = next,
    fireImmediately: true,
  );
  final router = GoRouter(
    initialLocation: Routes.path,
    refreshListenable: session,
    redirect: (context, state) => redirectFor(session.value, state.uri),
    routes: [
      GoRoute(path: Routes.path, builder: (context, state) => const PathPage()),
      GoRoute(
        path: Routes.startup,
        builder: (context, state) => const StartupPage(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: Routes.lessonPattern,
        builder: (context, state) =>
            LessonPage(lessonId: state.pathParameters['lessonId']!),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});
