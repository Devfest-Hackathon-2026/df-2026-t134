import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts Firestore document data to contract JSON so models parse one
/// format: [Timestamp] becomes an ISO 8601 UTC string, everything else stays.
///
/// Throws [FormatException] for missing documents and Firestore-only types
/// that the contracts never use.
Map<String, Object?> documentJson(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  if (data == null) {
    throw FormatException('Document ${doc.reference.path} does not exist');
  }
  return firestoreDataToJson(data, doc.reference.path);
}

/// Like [documentJson] and also checks that the `id` field equals the
/// document id (content documents are stored as `<collection>/<model id>`).
Map<String, Object?> contentDocumentJson(
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final json = documentJson(doc);
  if (json['id'] != doc.id) {
    throw FormatException(
      'Document ${doc.reference.path} has a different id field',
      json['id'],
    );
  }
  return json;
}

/// The conversion behind [documentJson]; [path] is only used in errors.
Map<String, Object?> firestoreDataToJson(
  Map<String, dynamic> map,
  String path,
) => {
  for (final MapEntry(:key, :value) in map.entries)
    key: _convertValue(value, '$path.$key'),
};

Object? _convertValue(Object? value, String path) => switch (value) {
  null || bool() || num() || String() => value,
  Timestamp() => value.toDate().toUtc().toIso8601String(),
  List() => [
    for (final (i, item) in value.indexed) _convertValue(item, '$path[$i]'),
  ],
  Map<String, dynamic>() => firestoreDataToJson(value, path),
  _ => throw FormatException('Unsupported Firestore value at $path', value),
};
