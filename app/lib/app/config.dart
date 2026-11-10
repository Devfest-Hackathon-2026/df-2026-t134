import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration passed with `--dart-define`.
class AppConfig {
  const AppConfig._(this.apiBaseUrl);

  /// Absolute http(s) URL of the learning API, without a trailing slash.
  final Uri apiBaseUrl;

  factory AppConfig.fromEnvironment() =>
      AppConfig.parse(const String.fromEnvironment('API_BASE_URL'));

  factory AppConfig.parse(String rawApiBaseUrl) {
    if (rawApiBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL is not set. Pass --dart-define=API_BASE_URL=<url>.',
      );
    }
    final uri = Uri.tryParse(rawApiBaseUrl);
    final isHttp =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isHttp || uri.host.isEmpty) {
      throw FormatException(
        'API_BASE_URL must be an absolute http(s) URL',
        rawApiBaseUrl,
      );
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return AppConfig._(uri.replace(path: path));
  }
}

/// Overridden in main() with the parsed configuration.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
