import 'package:ailearn/app/firebase_config.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseDefines defines({
  String backend = 'emulator',
  String projectId = 'demo-ailearn',
  String apiKey = 'demo-api-key',
  String appId = '1:000000000000:web:0000000000000000',
  String messagingSenderId = '000000000000',
  String storageBucket = 'demo-ailearn.appspot.com',
  String authDomain = 'demo-ailearn.firebaseapp.com',
  String appCheckSiteKey = '',
}) => FirebaseDefines(
  backend: backend,
  projectId: projectId,
  apiKey: apiKey,
  appId: appId,
  messagingSenderId: messagingSenderId,
  storageBucket: storageBucket,
  authDomain: authDomain,
  appCheckSiteKey: appCheckSiteKey,
);

void main() {
  test('parses the emulator configuration', () {
    final config = FirebaseConfig.parse(defines());

    expect(config.backend, isA<FirebaseEmulators>());
    final emulators = config.backend as FirebaseEmulators;
    expect(emulators.host, 'localhost');
    expect(emulators.authPort, 9099);
    expect(emulators.firestorePort, 8080);
    expect(config.options.projectId, 'demo-ailearn');
    expect(config.options.apiKey, 'demo-api-key');
    expect(config.options.appId, '1:000000000000:web:0000000000000000');
    expect(config.options.messagingSenderId, '000000000000');
    expect(config.options.storageBucket, 'demo-ailearn.appspot.com');
    expect(config.options.authDomain, 'demo-ailearn.firebaseapp.com');
  });

  test('parses a production configuration', () {
    final config = FirebaseConfig.parse(
      defines(
        backend: 'production',
        projectId: 'ailearn-prod',
        appCheckSiteKey: 'site-key',
      ),
    );

    expect(config.backend, isA<FirebaseProduction>());
    expect((config.backend as FirebaseProduction).appCheckSiteKey, 'site-key');
    expect(config.options.projectId, 'ailearn-prod');
  });

  test('production requires the App Check site key', () {
    expect(
      () => FirebaseConfig.parse(
        defines(backend: 'production', projectId: 'ailearn-prod'),
      ),
      throwsStateError,
    );
  });

  test('the emulators reject an App Check site key', () {
    expect(
      () => FirebaseConfig.parse(defines(appCheckSiteKey: 'site-key')),
      throwsFormatException,
    );
  });

  test('every define is required, including the backend switch', () {
    expect(() => FirebaseConfig.parse(defines(backend: '')), throwsStateError);
    expect(
      () => FirebaseConfig.parse(defines(projectId: '')),
      throwsStateError,
    );
    expect(() => FirebaseConfig.parse(defines(apiKey: '')), throwsStateError);
    expect(() => FirebaseConfig.parse(defines(appId: '')), throwsStateError);
    expect(
      () => FirebaseConfig.parse(defines(messagingSenderId: '')),
      throwsStateError,
    );
    expect(
      () => FirebaseConfig.parse(defines(storageBucket: '')),
      throwsStateError,
    );
    expect(
      () => FirebaseConfig.parse(defines(authDomain: '')),
      throwsStateError,
    );
  });

  test('rejects an unknown backend', () {
    expect(
      () => FirebaseConfig.parse(defines(backend: 'local')),
      throwsFormatException,
    );
  });

  test('emulators need a demo- project and production a real one', () {
    expect(
      () => FirebaseConfig.parse(defines(projectId: 'ailearn-prod')),
      throwsFormatException,
    );
    expect(
      () => FirebaseConfig.parse(
        defines(backend: 'production', appCheckSiteKey: 'site-key'),
      ),
      throwsFormatException,
    );
  });
}
