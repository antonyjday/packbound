import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:convoy_app/models/group.dart';

void main() {
  ConvoyGroup buildSample({String? ownerId}) => ConvoyGroup(
        id: 'group1',
        name: 'Road trip',
        createdBy: 'user1',
        inviteCode: 'AB2XQ9',
        inviteExpiresAt: Timestamp.now(),
        status: 'active',
        ownerId: ownerId,
      );

  group('ConvoyGroup.toMap', () {
    test('includes ownerId when set', () {
      final map = buildSample(ownerId: 'user1').toMap();
      expect(map['ownerId'], 'user1');
    });

    test('includes a null ownerId for an ownerless group', () {
      final map = buildSample().toMap();
      expect(map.containsKey('ownerId'), true);
      expect(map['ownerId'], null);
    });

    test('defaults membersCanInvite to true for a newly created group', () {
      final map = buildSample().toMap();
      expect(map['membersCanInvite'], true);
    });
  });
}
