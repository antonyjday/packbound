import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// hueViolet/hueAzure/hueGreen are reserved for route markers
// (destination/waypoints/start point in map_screen.dart's
// _buildRouteMarkers) so a member's color can never be confused with those.
const _memberHues = [
  BitmapDescriptor.hueRed,
  BitmapDescriptor.hueOrange,
  BitmapDescriptor.hueYellow,
  BitmapDescriptor.hueCyan,
  BitmapDescriptor.hueBlue,
  BitmapDescriptor.hueMagenta,
  BitmapDescriptor.hueRose,
];

/// Assigns each user a marker hue, guaranteed distinct as long as there are
/// no more than `_memberHues.length` users in [userIds] - callers (map
/// markers, the roster's matching legend dot) pass the same group's user
/// ids and get the same mapping back, since the assignment only depends on
/// the *set* of ids (sorted for a stable order), not on hashing individual
/// ids in isolation. A previous per-id hash-based approach could - and in
/// practice did, even with as few as 3 members - collide two different
/// users onto the same hue.
Map<String, double> markerHuesForUsers(Iterable<String> userIds) {
  final sorted = userIds.toSet().toList()..sort();
  return {
    for (var i = 0; i < sorted.length; i++) sorted[i]: _memberHues[i % _memberHues.length],
  };
}

/// Flutter Color matching a marker hue, for UI elements (e.g. the roster
/// avatar) that should visually correspond to that member's map marker.
Color colorForMarkerHue(double hue) =>
    HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
