import 'package:cloud_firestore/cloud_firestore.dart';
import 'route_plan.dart';

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
      };
}
