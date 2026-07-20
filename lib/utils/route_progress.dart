import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/route_plan.dart';

/// How close to a stop counts as "arrived" - used by [remainingLegs] to
/// decide whether a leg (the route's start point, or a waypoint) has
/// already been reached.
const waypointArrivalRadiusMeters = 500.0;

/// Legs (the start point, then waypoints, in order) not yet reached from
/// [myPosition]. A leg counts as reached if the member is currently within
/// [arrivalRadiusMeters] of it; everything through the *last* (highest-index)
/// leg reached is treated as passed. A simple proximity heuristic
/// recomputed fresh from wherever the member currently is, not persisted
/// "visited" state, so it self-corrects if someone backtracks.
///
/// Checking every leg for the last match - not stopping at the first leg
/// that's out of radius - matters once a member has moved on: someone
/// currently at waypoint 2 is far from the start point (they left its
/// radius miles ago) and would never re-enter it, so a first-mismatch
/// check would permanently get stuck treating the start point as
/// unreached and never look at waypoint 2 at all.
///
/// [manualSkipCount] additionally forces the first N legs to count as
/// passed regardless of proximity - MapScreen's "skip ahead" button's way
/// of saying "don't route me there, I'm not going" rather than "I haven't
/// gotten there yet". The two are combined with whichever has passed more
/// legs, since neither should be able to walk the other backwards.
List<RouteStop> remainingLegs(
  RouteStop myPosition,
  RoutePlan route, {
  int manualSkipCount = 0,
  double arrivalRadiusMeters = waypointArrivalRadiusMeters,
}) {
  final legs = [route.origin, ...route.waypoints];
  var lastReachedIndex = -1;
  for (var i = 0; i < legs.length; i++) {
    final distanceToStop = Geolocator.distanceBetween(
      myPosition.lat,
      myPosition.lng,
      legs[i].lat,
      legs[i].lng,
    );
    if (distanceToStop <= arrivalRadiusMeters) {
      lastReachedIndex = i;
    }
  }
  final passedCount = max(lastReachedIndex + 1, manualSkipCount).clamp(0, legs.length);
  return legs.sublist(passedCount);
}
