import 'package:ailearn/data/firebase/firestore_json.dart';
import 'package:ailearn/models/user_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts timestamps to ISO strings and keeps plain values', () {
    final json = firestoreDataToJson({
      'displayName': 'ひかり',
      'grade': 'j3',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 9, 1, 2, 3)),
      'nested': {
        'list': [1, true, null],
      },
    }, 'users/u');

    expect(json['createdAt'], '2026-11-09T01:02:03.000Z');
    expect(json['nested'], {
      'list': [1, true, null],
    });
    // The converted document parses with the contract model.
    final profile = UserProfile.fromJson(json..remove('nested'));
    expect(profile.createdAt, DateTime.utc(2026, 11, 9, 1, 2, 3));
  });

  test('rejects Firestore-only types the contracts never use', () {
    expect(
      () => firestoreDataToJson({'where': const GeoPoint(35, 139)}, 'units/u1'),
      throwsFormatException,
    );
  });
}
