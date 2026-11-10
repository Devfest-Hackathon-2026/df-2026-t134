import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/config.dart';
import '../data/providers.dart';
import 'api_client.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Overridden in main() with the App Check token source in production.
final appCheckTokenProvider = Provider<AppCheckTokenProvider>(
  (ref) => noAppCheckToken,
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    httpClient: ref.watch(httpClientProvider),
    idToken: ref.watch(authRepositoryProvider).currentIdToken,
    appCheckToken: ref.watch(appCheckTokenProvider),
  );
});

/// For providers whose failures the user retries by hand. Riverpod would
/// otherwise retry automatically and hide errors such as malformed documents.
Duration? noRetry(int retryCount, Object error) => null;
