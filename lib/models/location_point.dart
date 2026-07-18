import 'package:cloud_firestore/cloud_firestore.dart';

class LocationPoint {
  final String userId;
  final String displayName;
  final double lat;
  final double lng;
  final double heading;
  final double speed;
  final Timestamp updatedAt;

  LocationPoint({
    required this.userId,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.speed,
    required this.updatedAt,
  });

  factory LocationPoint.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return LocationPoint(
      userId: doc.id,
      displayName: data['displayName'] ?? 'Unknown',
      lat: (data['lat'] ?? 0).toDouble(),
      lng: (data['lng'] ?? 0).toDouble(),
      heading: (data['heading'] ?? 0).toDouble(),
      speed: (data['speed'] ?? 0).toDouble(),
      updatedAt: data['updatedAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'speed': speed,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Three-tier freshness instead of a single boolean:
  /// - live: updated very recently, trust the pin exactly
  /// - weak: a bit old — could be a tunnel, patchy signal, momentary GPS
  ///   drop. Worth a visual warning but not alarming.
  /// - lost: stale long enough that the group should assume this person
  ///   isn't actively broadcasting (app killed, phone off, out of range).
  SignalStatus get status {
    final seconds = secondsSinceUpdate;
    if (seconds <= 15) return SignalStatus.live;
    if (seconds <= 60) return SignalStatus.weak;
    return SignalStatus.lost;
  }

  int get secondsSinceUpdate {
    return DateTime.now().difference(updatedAt.toDate()).inSeconds;
  }

  /// True if stale enough to warrant a "signal lost" style warning.
  /// Kept for backwards compatibility with the old boolean check.
  bool get isStale => status != SignalStatus.live;

  String get lastSeenLabel {
    final s = secondsSinceUpdate;
    if (s < 5) return 'Just now';
    if (s < 60) return '${s}s ago';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ago';
    final h = m ~/ 60;
    return '${h}h ago';
  }
}

enum SignalStatus { live, weak, lost }
