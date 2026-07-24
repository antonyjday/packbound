import 'package:flutter/material.dart';

/// How a group is getting there - drives three things: the SetRouteScreen's
/// default "nearby" zoom level ([nearbyZoom] - a driving trip's plausible
/// range is a walker's "far too zoomed out"), which Directions API travel
/// mode actual routing uses ([directionsMode] - see DirectionsService.route),
/// and which quick-message presets are relevant (see quick_messages.dart).
/// Stored on the group doc as [name] (car/train/bicycle/walk); defaults to
/// [car] for any group created before this field existed.
enum TripType {
  car,
  train,
  bicycle,
  walk;

  static TripType fromName(String? name) => TripType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => TripType.car,
      );

  // "Bike" rather than "Bicycle" - short enough to fit the home screen's
  // 4-way segmented button on one line, same as the other three labels.
  String get label => switch (this) {
        TripType.car => 'Car',
        TripType.train => 'Train',
        TripType.bicycle => 'Bike',
        TripType.walk => 'Walk',
      };

  IconData get icon => switch (this) {
        TripType.car => Icons.directions_car,
        TripType.train => Icons.train,
        TripType.bicycle => Icons.directions_bike,
        TripType.walk => Icons.directions_walk,
      };

  // Roughly fits this mode's plausible trip range on a phone screen -
  // driving covers much more ground than walking, so the same fixed zoom
  // level would either be a pointless world view for a walk or a
  // near-useless close-up for a drive.
  double get nearbyZoom => switch (this) {
        TripType.car => 9.0, // ~50mi radius
        TripType.train => 8.0, // ~100mi radius - stations/lines span further
        TripType.bicycle => 12.0, // ~12mi radius
        TripType.walk => 14.0, // ~3mi radius
      };

  // Google Directions API's `mode` parameter. Note: transit directions
  // don't support the `waypoints` parameter at all - DirectionsService.route
  // drops them when this mode is used (see its own comment).
  String get directionsMode => switch (this) {
        TripType.car => 'driving',
        TripType.train => 'transit',
        TripType.bicycle => 'bicycling',
        TripType.walk => 'walking',
      };
}
