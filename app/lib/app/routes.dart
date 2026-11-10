/// Route paths, shared by the router and the pages that navigate.
abstract final class Routes {
  static const path = '/';
  static const startup = '/startup';
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const lessonPattern = '/lessons/:lessonId';

  static String lesson(String lessonId) => '/lessons/$lessonId';
}
