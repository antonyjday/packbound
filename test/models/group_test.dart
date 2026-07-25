import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:convoy_app/models/group.dart';
import 'package:convoy_app/models/trip_type.dart';

void main() {
  ConvoyGroup buildSample({String? ownerId, TripType tripType = TripType.car}) =>
      ConvoyGroup(
        id: 'group1',
        name: 'Road trip',
        createdBy: 'user1',
        inviteCode: 'AB2XQ9',
        inviteExpiresAt: Timestamp.now(),
        status: 'active',
        ownerId: ownerId,
        tripType: tripType,
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

    test('stores tripType by its name', () {
      final map = buildSample(tripType: TripType.bicycle).toMap();
      expect(map['tripType'], 'bicycle');
    });

    test('defaults routeSkipped to false for a newly created group', () {
      final map = buildSample().toMap();
      expect(map['routeSkipped'], false);
    });
  });

  group('ConvoyGroup.fromDoc', () {
    Future<ConvoyGroup> writeAndRead(Map<String, dynamic> data) async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('groups').doc('group1');
      await ref.set(data);
      return ConvoyGroup.fromDoc(await ref.get());
    }

    test('parses a stored tripType', () async {
      final group = await writeAndRead({
        'name': 'Trip',
        'createdBy': 'user1',
        'inviteCode': 'AB2XQ9',
        'inviteExpiresAt': Timestamp.now(),
        'status': 'active',
        'tripType': 'walk',
      });
      expect(group.tripType, TripType.walk);
    });

    test('defaults to TripType.car for a group with no tripType field', () async {
      // Simulates a group created before this field existed.
      final group = await writeAndRead({
        'name': 'Trip',
        'createdBy': 'user1',
        'inviteCode': 'AB2XQ9',
        'inviteExpiresAt': Timestamp.now(),
        'status': 'active',
      });
      expect(group.tripType, TripType.car);
    });

    test('parses a stored routeSkipped', () async {
      final group = await writeAndRead({
        'name': 'Trip',
        'createdBy': 'user1',
        'inviteCode': 'AB2XQ9',
        'inviteExpiresAt': Timestamp.now(),
        'status': 'active',
        'routeSkipped': true,
      });
      expect(group.routeSkipped, true);
    });

    test('defaults routeSkipped to false for a group with no such field', () async {
      // Simulates a group created before this field existed.
      final group = await writeAndRead({
        'name': 'Trip',
        'createdBy': 'user1',
        'inviteCode': 'AB2XQ9',
        'inviteExpiresAt': Timestamp.now(),
        'status': 'active',
      });
      expect(group.routeSkipped, false);
    });
  });
}
