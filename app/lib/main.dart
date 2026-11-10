import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/firebase_config.dart';
import 'core/providers.dart';
import 'core/voice_player.dart';
import 'data/firebase/firebase_auth_repository.dart';
import 'data/firebase/firebase_media.dart';
import 'data/firebase/firebase_setup.dart';
import 'data/firebase/firestore_repositories.dart';
import 'data/media.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'WDXL Lubrifont JP N',
    ], await rootBundle.loadString('assets/fonts/wdxl/OFL.txt'));
  });
  // Both fail fast when a --dart-define is missing or invalid.
  final config = AppConfig.fromEnvironment();
  final firebaseConfig = FirebaseConfig.fromEnvironment();
  final firebase = await connectFirebase(firebaseConfig);
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        appCheckTokenProvider.overrideWithValue(firebase.appCheckToken),
        authRepositoryProvider.overrideWithValue(
          FirebaseAuthRepository(firebase.auth),
        ),
        profileRepositoryProvider.overrideWithValue(
          FirestoreProfileRepository(firebase.firestore),
        ),
        contentRepositoryProvider.overrideWithValue(
          FirestoreContentRepository(firebase.firestore),
        ),
        progressRepositoryProvider.overrideWithValue(
          FirestoreProgressRepository(firebase.firestore),
        ),
        mediaRepositoryProvider.overrideWithValue(
          FirebaseMediaRepository(firebase.storage),
        ),
        voicePlayerProvider.overrideWith((ref) {
          final player = JustAudioVoicePlayer();
          ref.onDispose(player.dispose);
          return player;
        }),
      ],
      child: const AilearnApp(),
    ),
  );
}
