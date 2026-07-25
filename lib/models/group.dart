import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_plan.dart';
import 'trip_type.dart';

class ConvoyGroup {
  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;
  final Timestamp inviteExpiresAt;
  final String status; // 'active' | 'ended'
  final Timestamp? tripExpiresAt; // hard cap; owner can push this back via extendTrip()
  final int expiryWarningLevel; // 0 = none, 1 = early warning sent, 2 = final warning sent
  final RoutePlan? route; // owner-set shared trip plan; null if none set yet
  final bool membersCanInvite; // owner-controlled; false hides the share/invite button for non-owners

  // Owner has explicitly dismissed the "Set route" prompt for this trip -
  // e.g. a group that already knows a familiar route and just wants live
  // positions, not turn-by-turn. Purely suppresses the map screen's CTA
  // banner; "Set route"/"Edit route" stays available in the owner's menu
  // regardless, and setting a real route makes this moot either way since
  // the banner's own condition already requires route == null.
  final bool routeSkipped;

  // The *current* owner's uid - distinct from createdBy (which never
  // changes). Kept in sync with the members subcollection's role field
  // (see GroupService.leaveGroup) purely so firestore.rules can cheaply
  // tell "this group currently has no owner" (everyone left, including
  // the owner) without being able to query the members subcollection for
  // emptiness directly - null means ownerless, and GroupService.
  // joinGroupByInviteCode has the next person to rejoin inherit it.
  final String? ownerId;

  // How the group is getting there - see trip_type.dart. Defaults to car,
  // both for a brand new group and for any group created before this field
  // existed (fromDoc's fallback).
  final TripType tripType;

  ConvoyGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
    required this.inviteExpiresAt,
    required this.status,
    this.tripExpiresAt,
    this.expiryWarningLevel = 0,
    this.route,
    this.membersCanInvite = true,
    this.routeSkipped = false,
    this.ownerId,
    this.tripType = TripType.car,
  });

  factory ConvoyGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final routeData = data['route'];
    return ConvoyGroup(
      id: doc.id,
      name: data['name'] ?? '',
      createdBy: data['createdBy'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      inviteExpiresAt: data['inviteExpiresAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'active',
      tripExpiresAt: data['tripExpiresAt'],
      expiryWarningLevel: data['expiryWarningLevel'] ?? 0,
      route: routeData != null
          ? RoutePlan.fromMap(Map<String, dynamic>.from(routeData))
          : null,
      membersCanInvite: data['membersCanInvite'] ?? true,
      routeSkipped: data['routeSkipped'] ?? false,
      ownerId: data['ownerId'],
      tripType: TripType.fromName(data['tripType']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'createdBy': createdBy,
        'inviteCode': inviteCode,
        'inviteExpiresAt': inviteExpiresAt,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActivityAt': FieldValue.serverTimestamp(),
        'tripExpiresAt': tripExpiresAt,
        'expiryWarningLevel': 0,
        'membersCanInvite': true,
        'routeSkipped': false,
        'ownerId': ownerId,
        'tripType': tripType.name,
      };
}
