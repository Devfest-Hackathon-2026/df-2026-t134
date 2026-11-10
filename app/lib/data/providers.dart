import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repositories.dart';

// Overridden in main() with the Firebase implementations and in tests with fakes.

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      throw UnimplementedError('authRepositoryProvider must be overridden'),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) =>
      throw UnimplementedError('profileRepositoryProvider must be overridden'),
);

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) =>
      throw UnimplementedError('contentRepositoryProvider must be overridden'),
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) =>
      throw UnimplementedError('progressRepositoryProvider must be overridden'),
);
