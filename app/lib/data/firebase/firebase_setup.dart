import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../app/firebase_config.dart';
import '../../core/api_client.dart';

/// SDK instances bound to one initialized Firebase app.
class FirebaseServices {
  const FirebaseServices({
    required this.auth,
    required this.firestore,
    required this.storage,
    required this.appCheckToken,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  /// Pre-generated story pictures and voices (read only).
  final FirebaseStorage storage;

  /// App Check token for API calls; always null with the emulators.
  final AppCheckTokenProvider appCheckToken;
}

/// Initializes Firebase and, for [FirebaseEmulators], points Auth,
/// Firestore and Storage at the local emulators before anything else touches them. In
/// production App Check is activated with reCAPTCHA Enterprise.
Future<FirebaseServices> connectFirebase(FirebaseConfig config) async {
  final app = await Firebase.initializeApp(options: config.options);
  final auth = FirebaseAuth.instanceFor(app: app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  final storage = FirebaseStorage.instanceFor(app: app);
  switch (config.backend) {
    case FirebaseEmulators(
      :final host,
      :final authPort,
      :final firestorePort,
      :final storagePort,
    ):
      await auth.useAuthEmulator(host, authPort);
      firestore.useFirestoreEmulator(host, firestorePort);
      await storage.useStorageEmulator(host, storagePort);
      return FirebaseServices(
        auth: auth,
        firestore: firestore,
        storage: storage,
        appCheckToken: noAppCheckToken,
      );
    case FirebaseProduction(:final appCheckSiteKey):
      final appCheck = FirebaseAppCheck.instanceFor(app: app);
      await appCheck.activate(
        providerWeb: ReCaptchaEnterpriseProvider(appCheckSiteKey),
      );
      await appCheck.setTokenAutoRefreshEnabled(true);
      return FirebaseServices(
        auth: auth,
        firestore: firestore,
        storage: storage,
        appCheckToken: appCheck.getToken,
      );
  }
}
