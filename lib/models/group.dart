import 'package:cloud_firestore/cloud_firestore.dart';

class ConvoyGroup {
  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;
  final Timestamp inviteExpiresAt;
  final String status; // 'active' | 'ended'
  final Timestamp? tripExpiresAt; // hard cap; owner can push this back via extendTrip()
  final int expiryWarningLevel; // 0 = none, 1 = early warning sent, 2 = final warning sent

  ConvoyGroup({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
    required this.inviteExpiresAt,
    required this.status,
    this.tripExpiresAt,
    this.expiryWarningLevel = 0,
  });

  factory ConvoyGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ConvoyGroup(
      id: doc.id,
      name: data['name'] ?? '',
      createdBy: data['createdBy'] ?? '',
      inviteCode: data['inviteCode'] ?? '',
      inviteExpiresAt: data['inviteExpiresAt'] ?? Timestamp.now(),
      status: data['status'] ?? 'active',
      tripExpiresAt: data['tripExpiresAt'],
      expiryWarningLevel: data['expiryWarningLevel'] ?? 0,
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
      };
}
