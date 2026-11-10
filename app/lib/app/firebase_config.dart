import 'package:firebase_core/firebase_core.dart';

/// Where the Firebase SDK talks to.
sealed class FirebaseBackend {
  const FirebaseBackend();
}

/// Local Emulator Suite started by `make up` (see compose.yaml).
final class FirebaseEmulators extends FirebaseBackend {
  const FirebaseEmulators();

  /// The browser reaches the emulators through the ports published on the host.
  final String host = 'localhost';
  final int authPort = 9099;
  final int firestorePort = 8080;
  final int storagePort = 9199;
}

/// The real Firebase project. Requests to the API carry an App Check token
/// from reCAPTCHA Enterprise ([appCheckSiteKey] is the public site key).
final class FirebaseProduction extends FirebaseBackend {
  const FirebaseProduction({required this.appCheckSiteKey});

  final String appCheckSiteKey;
}

/// Raw `--dart-define` values, kept separate so [FirebaseConfig.parse] can be
/// tested without compile-time constants.
class FirebaseDefines {
  const FirebaseDefines({
    required this.backend,
    required this.projectId,
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.storageBucket,
    required this.authDomain,
    this.appCheckSiteKey = '',
  });

  const FirebaseDefines.fromEnvironment()
    : backend = const String.fromEnvironment('FIREBASE_BACKEND'),
      projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      apiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
      appId = const String.fromEnvironment('FIREBASE_APP_ID'),
      messagingSenderId = const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      storageBucket = const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      authDomain = const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      appCheckSiteKey = const String.fromEnvironment('APP_CHECK_SITE_KEY');

  final String backend;
  final String projectId;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String storageBucket;
  final String authDomain;

  /// Only for `production`; must be empty for the emulators.
  final String appCheckSiteKey;
}

/// Firebase web configuration passed with `--dart-define`.
///
/// Every value is required, including `FIREBASE_BACKEND` (`emulator` or
/// `production`), so a release build without explicit values fails at startup
/// instead of silently talking to the wrong backend.
class FirebaseConfig {
  const FirebaseConfig._(this.options, this.backend);

  final FirebaseOptions options;
  final FirebaseBackend backend;

  factory FirebaseConfig.fromEnvironment() =>
      FirebaseConfig.parse(const FirebaseDefines.fromEnvironment());

  factory FirebaseConfig.parse(FirebaseDefines defines) {
    String required(String name, String value) {
      if (value.isEmpty) {
        throw StateError('$name is not set. Pass --dart-define=$name=<value>.');
      }
      return value;
    }

    final backend = switch (required('FIREBASE_BACKEND', defines.backend)) {
      'emulator' when defines.appCheckSiteKey.isNotEmpty =>
        throw FormatException(
          'APP_CHECK_SITE_KEY is only for FIREBASE_BACKEND=production',
          defines.appCheckSiteKey,
        ),
      'emulator' => const FirebaseEmulators(),
      'production' => FirebaseProduction(
        appCheckSiteKey: required(
          'APP_CHECK_SITE_KEY',
          defines.appCheckSiteKey,
        ),
      ),
      final other => throw FormatException(
        'FIREBASE_BACKEND must be "emulator" or "production"',
        other,
      ),
    };
    final projectId = required('FIREBASE_PROJECT_ID', defines.projectId);
    // The emulators only run offline "demo-" projects, and a "demo-" project
    // does not exist in production.
    final isDemoProject = projectId.startsWith('demo-');
    switch (backend) {
      case FirebaseEmulators() when !isDemoProject:
        throw FormatException(
          'FIREBASE_PROJECT_ID must start with "demo-" for the emulators',
          projectId,
        );
      case FirebaseProduction() when isDemoProject:
        throw FormatException(
          'FIREBASE_PROJECT_ID must be a real project in production',
          projectId,
        );
      default:
        break;
    }
    final options = FirebaseOptions(
      projectId: projectId,
      apiKey: required('FIREBASE_API_KEY', defines.apiKey),
      appId: required('FIREBASE_APP_ID', defines.appId),
      messagingSenderId: required(
        'FIREBASE_MESSAGING_SENDER_ID',
        defines.messagingSenderId,
      ),
      storageBucket: required('FIREBASE_STORAGE_BUCKET', defines.storageBucket),
      // signInWithPopup needs it, also with the Auth emulator.
      authDomain: required('FIREBASE_AUTH_DOMAIN', defines.authDomain),
    );
    return FirebaseConfig._(options, backend);
  }
}
