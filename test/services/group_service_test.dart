import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/route_plan.dart';
import 'package:convoy_app/services/group_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late GroupService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = GroupService(firestore: db);
  });

  Future<Map<String, dynamic>?> memberData(String groupId, String uid) async {
    final doc = await db.collection('groups').doc(groupId).collection('members').doc(uid).get();
    return doc.data();
  }

  Future<Map<String, dynamic>?> groupData(String groupId) async {
    final doc = await db.collection('groups').doc(groupId).get();
    return doc.data();
  }

  group('createGroup', () {
    test('creates the group doc and an owner membership doc', () async {
      final group = await service.createGroup(name: 'Road trip', ownerId: 'owner-1');

      expect(group.name, 'Road trip');
      expect(group.createdBy, 'owner-1');
      expect(group.ownerId, 'owner-1');
      expect(group.status, 'active');

      final member = await memberData(group.id, 'owner-1');
      expect(member?['role'], 'owner');
      expect(member?['sharingEnabled'], true);
    });

    test('generates a 6-character invite code from the expected charset', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      expect(group.inviteCode.length, 6);
      // No ambiguous chars (0/O, 1/I/L) - see GroupService._generateInviteCode.
      expect(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$').hasMatch(group.inviteCode), true);
    });
  });

  group('joinGroupByInviteCode', () {
    test('joins an existing owned group as an ordinary member', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');

      final joined = await service.joinGroupByInviteCode(
        inviteCode: group.inviteCode,
        userId: 'member-2',
      );

      expect(joined.id, group.id);
      final member = await memberData(group.id, 'member-2');
      expect(member?['role'], 'member');
      // Owner untouched.
      expect((await groupData(group.id))?['ownerId'], 'owner-1');
    });

    test('is case-insensitive on the invite code', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');

      await service.joinGroupByInviteCode(
        inviteCode: group.inviteCode.toLowerCase(),
        userId: 'member-2',
      );

      expect(await memberData(group.id, 'member-2'), isNotNull);
    });

    test('inherits ownership when the group is currently ownerless', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      // Simulate everyone having left - see leaveGroup's ownerless case.
      await db.collection('groups').doc(group.id).update({'ownerId': null});

      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');

      final member = await memberData(group.id, 'member-2');
      expect(member?['role'], 'owner');
      expect((await groupData(group.id))?['ownerId'], 'member-2');
    });

    test(
      're-entering the invite code as an existing owner does not demote them '
      '(regression: joinGroupByInviteCode used to only check "is the group '
      'ownerless", not "am I already a member")',
      () async {
        final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');

        await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'owner-1');

        final member = await memberData(group.id, 'owner-1');
        expect(member?['role'], 'owner');
        expect((await groupData(group.id))?['ownerId'], 'owner-1');
      },
    );

    test('re-entering the invite code as an existing member is a no-op', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');

      // Re-join - should not throw or change anything.
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');

      final member = await memberData(group.id, 'member-2');
      expect(member?['role'], 'member');
    });

    test('throws for an invite code that matches no active group', () async {
      expect(
        () => service.joinGroupByInviteCode(inviteCode: 'ZZZZZZ', userId: 'member-2'),
        throwsA(anything),
      );
    });

    test('throws for an expired invite code', () async {
      final group = await service.createGroup(
        name: 'Trip',
        ownerId: 'owner-1',
        inviteValidFor: const Duration(seconds: -1), // already expired
      );

      expect(
        () => service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2'),
        throwsA(anything),
      );
    });

    test('does not match an ended group\'s invite code', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.endGroup(group.id);

      expect(
        () => service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2'),
        throwsA(anything),
      );
    });
  });

  group('leaveGroup', () {
    test('promotes the longest-joined remaining member to owner', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-3');

      await service.leaveGroup(group.id, 'owner-1');

      // member-2 joined before member-3, so they should inherit ownership.
      expect((await groupData(group.id))?['ownerId'], 'member-2');
      expect((await memberData(group.id, 'member-2'))?['role'], 'owner');
      expect(await memberData(group.id, 'owner-1'), isNull);
    });

    test('clears ownerId when the owner leaves with nobody else remaining', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');

      await service.leaveGroup(group.id, 'owner-1');

      expect((await groupData(group.id))?['ownerId'], isNull);
      expect(await memberData(group.id, 'owner-1'), isNull);
    });

    test('an ordinary member leaving does not touch ownership', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');

      await service.leaveGroup(group.id, 'member-2');

      expect((await groupData(group.id))?['ownerId'], 'owner-1');
      expect(await memberData(group.id, 'member-2'), isNull);
    });

    test('also deletes the leaving member\'s location doc', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await db.collection('groups').doc(group.id).collection('locations').doc('owner-1').set({
        'lat': 1.0,
        'lng': 2.0,
      });

      await service.leaveGroup(group.id, 'owner-1');

      final loc =
          await db.collection('groups').doc(group.id).collection('locations').doc('owner-1').get();
      expect(loc.exists, false);
    });
  });

  group('removeMember', () {
    test('deletes the target\'s membership and location docs', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.joinGroupByInviteCode(inviteCode: group.inviteCode, userId: 'member-2');
      await db.collection('groups').doc(group.id).collection('locations').doc('member-2').set({
        'lat': 1.0,
        'lng': 2.0,
      });

      await service.removeMember(group.id, 'member-2');

      expect(await memberData(group.id, 'member-2'), isNull);
      final loc = await db
          .collection('groups')
          .doc(group.id)
          .collection('locations')
          .doc('member-2')
          .get();
      expect(loc.exists, false);
    });
  });

  group('extendTrip', () {
    test('resets tripExpiresAt to ~24h from now and clears the warning level', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await db.collection('groups').doc(group.id).update({'expiryWarningLevel': 2});

      final before = DateTime.now();
      await service.extendTrip(group.id);
      final after = DateTime.now();

      final data = await groupData(group.id);
      final tripExpiresAt = (data?['tripExpiresAt'] as Timestamp).toDate();
      expect(tripExpiresAt.isAfter(before.add(const Duration(hours: 23, minutes: 59))), true);
      expect(tripExpiresAt.isBefore(after.add(const Duration(hours: 24, minutes: 1))), true);
      expect(data?['expiryWarningLevel'], 0);
    });
  });

  group('setMembersCanInvite / setRoute / clearRoute / endGroup', () {
    test('setMembersCanInvite updates the flag', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.setMembersCanInvite(group.id, false);
      expect((await groupData(group.id))?['membersCanInvite'], false);
    });

    test('setRoute stores the route and clearRoute removes it', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      final route = RoutePlan(
        origin: RouteStop(lat: 1, lng: 2),
        destination: RouteStop(lat: 3, lng: 4),
        waypoints: const [],
        polyline: 'abc',
        distanceMeters: 100,
        durationSeconds: 60,
      );

      await service.setRoute(group.id, route);
      expect((await groupData(group.id))?['route'], isNotNull);

      await service.clearRoute(group.id);
      expect((await groupData(group.id))?['route'], isNull);
    });

    test('endGroup marks the group ended', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      await service.endGroup(group.id);
      expect((await groupData(group.id))?['status'], 'ended');
    });
  });

  group('sendQuickMessage / messagesStream', () {
    test('sends a message and it appears in the stream, newest first', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');

      await service.sendQuickMessage(
        group.id,
        senderId: 'owner-1',
        senderName: 'Owner',
        text: 'Pulling over',
      );
      await Future.delayed(const Duration(milliseconds: 5));
      await service.sendQuickMessage(
        group.id,
        senderId: 'member-2',
        senderName: 'Member Two',
        text: 'Need gas',
      );

      final messages = await service.messagesStream(group.id).first;
      expect(messages.length, 2);
      expect(messages.first.text, 'Need gas'); // most recently sent
      expect(messages.first.senderName, 'Member Two');
      expect(messages.last.text, 'Pulling over');
    });

    test('messagesStream respects the limit', () async {
      final group = await service.createGroup(name: 'Trip', ownerId: 'owner-1');
      for (var i = 0; i < 5; i++) {
        await service.sendQuickMessage(
          group.id,
          senderId: 'owner-1',
          senderName: 'Owner',
          text: 'Message $i',
        );
      }

      final messages = await service.messagesStream(group.id, limit: 3).first;
      expect(messages.length, 3);
    });
  });
}
