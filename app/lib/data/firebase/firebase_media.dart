import 'package:firebase_storage/firebase_storage.dart';

import '../media.dart';

/// [MediaRepository] on the project's Cloud Storage bucket
/// (firebase/storage.rules lets signed-in users read `images/` and `audio/`).
class FirebaseMediaRepository implements MediaRepository {
  const FirebaseMediaRepository(this._storage);

  final FirebaseStorage _storage;

  @override
  Future<Uri> downloadUrl(String storagePath) async =>
      Uri.parse(await _storage.ref(storagePath).getDownloadURL());
}
