import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  final passedCount = max(
    lastReachedIndex + 1,
    manualSkipCount,
  ).clamp(0, legs.length);
  return legs.sublist(passedCount);
}

/// How close the owner must get to a waypoint before it's dropped from the
/// group's *shared* route (see MapScreen's _maybeRerouteSharedRoute) - a
/// tighter radius than [waypointArrivalRadiusMeters] above, since dropping
/// a stop from everyone's shared plan for good is a more consequential,
/// harder-to-undo action than just fading it from one viewer's own ETA
/// overlay.
const ownerWaypointClearRadiusMeters = 100.0;

/// How close the owner must be to the route's start point before
/// MapScreen's "Start trip" button appears - deliberately the same
/// tightness as [ownerWaypointClearRadiusMeters], for the same reason:
/// this also drops/replaces a leg of the group's shared route for good,
/// so it shouldn't offer to fire from a rough "somewhere nearby" guess.
const startPointArrivalRadiusMeters = 100.0;

/// Waypoints not yet reached by [position], in order - the same
/// "furthest-in-sequence leg reached wins" heuristic as [remainingLegs],
/// but scoped to just the waypoint list (never the start point) since
/// this is used to decide which waypoints the *owner's* device should
/// drop from the shared route as they're passed. Rerouting always
/// re-originates from the owner's actual current position rather than
/// snapping to whichever waypoint was just reached, so there's no need to
/// treat the start point as a leg here the way [remainingLegs] does.
List<RouteStop> remainingWaypoints(
  RouteStop position,
  List<RouteStop> waypoints, {
  double arrivalRadiusMeters = ownerWaypointClearRadiusMeters,
}) {
  var lastReachedIndex = -1;
  for (var i = 0; i < waypoints.length; i++) {
    final distance = Geolocator.distanceBetween(
      position.lat,
      position.lng,
      waypoints[i].lat,
      waypoints[i].lng,
    );
    if (distance <= arrivalRadiusMeters) {
      lastReachedIndex = i;
    }
  }
  return waypoints.sublist(lastReachedIndex + 1);
}

/// Meters the owner must drift from the set route's line before it's
/// treated as a real detour worth recalculating for, rather than GPS
/// noise or briefly being on a parallel side road.
const routeDeviationThresholdMeters = 150.0;

/// Shortest distance in meters from [position] to the polyline formed by
/// [routePoints], approximated as the distance to the nearest vertex
/// rather than a true point-to-segment projection. The Directions API's
/// per-step polylines are dense enough (a vertex every few tens of metres
/// on a real road) that the difference is well within
/// [routeDeviationThresholdMeters]'s margin, and this avoids the geometry
/// edge cases of a full segment projection for a threshold check that
/// only needs to be roughly right.
double distanceFromRouteMeters(RouteStop position, List<LatLng> routePoints) {
  if (routePoints.isEmpty) return double.infinity;
  var minDistance = double.infinity;
  for (final point in routePoints) {
    final distance = Geolocator.distanceBetween(
      position.lat,
      position.lng,
      point.latitude,
      point.longitude,
    );
    if (distance < minDistance) minDistance = distance;
  }
  return minDistance;
}

/// How much nearer the route's own start point has to be than the rest of
/// the route before [isHeadingToRouteStart] stops calling it "still on the
/// way to the start" - small, since it only exists to absorb the fact that
/// the polyline's first vertex and the stored origin are never *exactly*
/// the same coordinate (the Directions API snaps the origin to the road).
const routeStartApproachToleranceMeters = 50.0;

/// Whether [position] hasn't joined the route anywhere along its length yet
/// and is still travelling towards its start - true when the route's own
/// origin is, near enough, the closest part of the whole route.
///
/// Separates the two very different situations that both read as "far from
/// the route": someone who simply hasn't set off for the meeting point yet,
/// and someone who has genuinely detoured off a route they were already
/// driving. Only the second is worth recalculating for. Without this,
/// setting a start point anywhere other than where the owner is sitting
/// made every pre-departure tick look like a
/// [routeDeviationThresholdMeters] detour, so the automatic reroute would
/// overwrite the deliberately-chosen start point with the owner's current
/// position a couple of minutes after they set it.
///
/// Stateless on purpose, like every other progress check in this file: it
/// asks "which part of the route am I nearest to *right now*", so it stops
/// applying the moment the traveler is nearest to any later part of the
/// route - including after they've driven past the start point and off
/// course later on, which is exactly when detour detection should resume.
bool isHeadingToRouteStart(
  RouteStop position,
  RouteStop origin,
  List<LatLng> routePoints, {
  double toleranceMeters = routeStartApproachToleranceMeters,
}) {
  if (routePoints.isEmpty) return false;
  final distanceToOrigin = Geolocator.distanceBetween(
    position.lat,
    position.lng,
    origin.lat,
    origin.lng,
  );
  return distanceToOrigin <=
      distanceFromRouteMeters(position, routePoints) + toleranceMeters;
}
