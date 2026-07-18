import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';
import '../models/route_plan.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Mirrors functions/src/config.ts TRIP_LIFETIME_HOURS / EXTENSION_HOURS.
  // Keep these in sync if you change the server-side thresholds.
  static const Duration tripLifetime = Duration(hours: 24);
  static const Duration tripExtension = Duration(hours: 24);

  String _generateInviteCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

  /// Creates a new convoy group and adds the creator as owner.
  Future<ConvoyGroup> createGroup({
    required String name,
    required String ownerId,
    Duration inviteValidFor = const Duration(hours: 24),
  }) async {
    final groupRef = _db.collection('groups').doc();
    final inviteCode = _generateInviteCode();
    final expiresAt =
        Timestamp.fromDate(DateTime.now().add(inviteValidFor));

    final group = ConvoyGroup(
      id: groupRef.id,
      name: name,
      createdBy: ownerId,
      inviteCode: inviteCode,
      inviteExpiresAt: expiresAt,
      status: 'active',
      tripExpiresAt: Timestamp.fromDate(DateTime.now().add(tripLifetime)),
    );

    // Deliberately two sequential writes, not a batch/transaction: the
    // members-doc create rule needs to `get()` this group doc to confirm
    // `createdBy`, and that get() does not see sibling writes from the same
    // batch/transaction - it would still find the group doc nonexistent and
    // deny the whole write. Awaiting the group doc's creation first ensures
    // it's already committed by the time the membership write is evaluated.
    await groupRef.set(group.toMap());
    await groupRef.collection('members').doc(ownerId).set({
      'joinedAt': FieldValue.serverTimestamp(),
      'role': 'owner',
      'sharingEnabled': true,
    });

    return group;
  }

  /// Looks up a group by invite code, validates it hasn't expired,
  /// and adds the given user as a member.
  Future<ConvoyGroup> joinGroupByInviteCode({
    required String inviteCode,
    required String userId,
  }) async {
    final query = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid or expired invite code');
    }

    final doc = query.docs.first;
    final group = ConvoyGroup.fromDoc(doc);

    if (group.inviteExpiresAt.toDate().isBefore(DateTime.now())) {
      throw Exception('This invite code has expired');
    }

    await doc.reference.collection('members').doc(userId).set({
      'joinedAt': FieldValue.serverTimestamp(),
      'role': 'member',
      'sharingEnabled': true,
    });

    return group;
  }

  Future<void> endGroup(String groupId) {
    return _db.collection('groups').doc(groupId).update({'status': 'ended'});
  }

  /// Owner-only action: pushes the trip's hard-cap expiry out by another
  /// `tripExtension` (24h by default), measured from now - not from the
  /// old deadline - so "extend" always gives a full fresh window rather
  /// than compounding partial time left. Also resets the warning level
  /// so the owner gets warned again as the *new* deadline approaches.
  Future<void> extendTrip(String groupId) {
    return _db.collection('groups').doc(groupId).update({
      'tripExpiresAt': Timestamp.fromDate(DateTime.now().add(tripExtension)),
      'expiryWarningLevel': 0,
    });
  }

  /// Owner-only: sets (or replaces) the group's shared trip plan. Stored as a
  /// plain field on the group doc, so it's covered by the existing
  /// isOwner()-gated `update` rule - no separate security rule needed.
  Future<void> setRoute(String groupId, RoutePlan route) {
    return _db.collection('groups').doc(groupId).update({'route': route.toMap()});
  }

  Future<void> clearRoute(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .update({'route': FieldValue.delete()});
  }

  Future<void> leaveGroup(String groupId, String userId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(userId)
        .delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> memberStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .snapshots();
  }
}
