import 'package:cloud_firestore/cloud_firestore.dart';

class RouteStop {
  final double lat;
  final double lng;

  RouteStop({required this.lat, required this.lng});

  factory RouteStop.fromMap(Map<String, dynamic> map) => RouteStop(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};
}

/// One turn-by-turn instruction from the Directions API, in route order.
/// Only ever produced transiently by [DirectionsService.route] for
/// whichever device just called it (the shared/stored [RoutePlan] never
/// includes these - see [RoutePlan.steps]), so there's no fromMap/toMap:
/// nothing persists this to Firestore.
class RouteStep {
  final String instruction;
  final String? maneuver;
  final int distanceMeters;
  final RouteStop startLocation;
  final RouteStop endLocation;

  RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.startLocation,
    required this.endLocation,
  });
}

/// A group's shared planned trip: the trip's starting point (`origin` -
/// wherever the owner was when they set it, unless they picked a different
/// starting point on the map), the ordered stops along the way
/// (`waypoints`), and the final `destination` - resolved into an actual
/// driving route (`polyline`) via the Directions API once, on the owner's
/// device, at save time. Every member just decodes and renders the same
/// stored polyline.
class RoutePlan {
  final RouteStop origin;
  final RouteStop destination;
  final List<RouteStop> waypoints;
  final String polyline;
  final int distanceMeters;
  final int durationSeconds;

  // Turn-by-turn steps for whichever origin/destination this particular
  // RoutePlan was resolved from - populated on the per-device "my live
  // route" recalculation in MapScreen (see _recalculateMyEta), empty for
  // the shared plan fetched from Firestore (fromMap doesn't read it, and
  // toMap doesn't write it - every viewer's own turn-by-turn only makes
  // sense from their own position, not the owner's, so there's nothing
  // meaningful to share).
  final List<RouteStep> steps;

  RoutePlan({
    required this.origin,
    required this.destination,
    required this.waypoints,
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.steps = const [],
  });

  factory RoutePlan.fromMap(Map<String, dynamic> map) => RoutePlan(
        origin: RouteStop.fromMap(Map<String, dynamic>.from(map['origin'])),
        destination:
            RouteStop.fromMap(Map<String, dynamic>.from(map['destination'])),
        waypoints: (map['waypoints'] as List<dynamic>? ?? [])
            .map((w) => RouteStop.fromMap(Map<String, dynamic>.from(w)))
            .toList(),
        polyline: map['polyline'] ?? '',
        distanceMeters: (map['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'origin': origin.toMap(),
        'destination': destination.toMap(),
        'waypoints': waypoints.map((w) => w.toMap()).toList(),
        'polyline': polyline,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'setAt': FieldValue.serverTimestamp(),
      };
}
