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

/// Deterministic per-user marker hue - the same user always gets the same
/// color across sessions/devices/viewers, derived from their stable uid.
/// Used for both the map marker itself and the roster's matching legend dot.
double markerHueForUser(String userId) =>
    _memberHues[userId.hashCode.abs() % _memberHues.length];

/// Flutter Color matching a marker hue, for UI elements (e.g. the roster
/// avatar) that should visually correspond to that member's map marker.
Color colorForMarkerHue(double hue) =>
    HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
