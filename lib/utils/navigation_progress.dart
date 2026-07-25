import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/route_plan.dart';

/// Below this speed (m/s, ~5.6mph), GPS-reported heading is unreliable -
/// noisy or just stale from the last time the device was actually moving -
/// and shouldn't be trusted for anything heading-dependent (relabeling a
/// turn instruction relative to it, or camera follow-mode in MapScreen).
/// Raised from an earlier 1.0 (~2.2mph) after live testing showed even
/// "moving" GPS headings around walking pace were noisy enough to
/// occasionally misclassify a straight-ahead step as a U-turn.
const movingSpeedThresholdMps = 2.5;

/// Below this length, a step's start->end bearing is too short a baseline
/// to trust as "the direction this road actually points" - e.g. a route
/// recalculated from the live-GPS-snapped-to-road origin often has a tiny
/// first "step" from that snapped point to the nearest real intersection,
/// whose bearing can point almost anywhere and has nothing to do with the
/// road's real heading. Only relevant to [classifyTurnManeuver]'s use on a
/// leg's first step (see its doc comment) - every other step already has a
/// real API-provided maneuver and doesn't go through this heading compare.
const minReliableStepBearingMeters = 25.0;

/// How close to a turn-by-turn step's endpoint counts as "reached" - much
/// tighter than [waypointArrivalRadiusMeters] in route_progress.dart, since
/// consecutive maneuvers can be a lot closer together than planned stops.
const stepArrivalRadiusMeters = 40.0;

/// The next turn-by-turn instruction still ahead of [myPosition], out of
/// [steps] (already in route order) - or null once every step's endpoint
/// has been reached (arrived). Same last-match proximity heuristic as
/// [remainingLegs] in route_progress.dart: checks every step for the last
/// one within [arrivalRadiusMeters] rather than stopping at the first
/// mismatch, so it self-corrects from wherever the device actually is
/// rather than getting stuck on an already-passed maneuver.
RouteStep? nextNavigationStep(
  RouteStop myPosition,
  List<RouteStep> steps, {
  double arrivalRadiusMeters = stepArrivalRadiusMeters,
}) {
  if (steps.isEmpty) return null;
  var lastReachedIndex = -1;
  for (var i = 0; i < steps.length; i++) {
    final distanceToStepEnd = Geolocator.distanceBetween(
      myPosition.lat,
      myPosition.lng,
      steps[i].endLocation.lat,
      steps[i].endLocation.lng,
    );
    if (distanceToStepEnd <= arrivalRadiusMeters) {
      lastReachedIndex = i;
    }
  }
  final nextIndex = lastReachedIndex + 1;
  if (nextIndex >= steps.length) return null;
  return steps[nextIndex];
}

/// Classifies the turn from [fromHeadingDeg] (this device's current
/// direction of travel) to [toHeadingDeg] (the bearing of the upcoming
/// step) into the same maneuver vocabulary the Directions API itself uses
/// ('turn-left', 'turn-slight-right', ...), or null for "continue straight"
/// - which is also how the API represents it (its `maneuver` field is only
/// ever set for an actual turn). Only meant for steps where the API's own
/// `maneuver` is null: those are its "Head (compass direction) on/toward
/// X" steps (always the first step of a leg), phrased relative to compass
/// direction rather than the traveler's own heading since the API has no
/// prior direction to turn relative to yet - this fills that gap using the
/// device's actual live heading instead, e.g. so someone heading south who
/// needs to head east next sees "turn left", not "head east". Every other
/// step already carries a real maneuver from the API, itself already
/// relative to the route's own direction of travel - left alone.
String? classifyTurnManeuver(double fromHeadingDeg, double toHeadingDeg) {
  var diff = (toHeadingDeg - fromHeadingDeg) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  final magnitude = diff.abs();
  if (magnitude < 15) return null;
  if (magnitude < 45) return diff > 0 ? 'turn-slight-right' : 'turn-slight-left';
  if (magnitude < 135) return diff > 0 ? 'turn-right' : 'turn-left';
  if (magnitude < 160) return diff > 0 ? 'turn-sharp-right' : 'turn-sharp-left';
  return diff > 0 ? 'uturn-right' : 'uturn-left';
}

final _headInstructionPattern =
    RegExp(r'^Head\s+\S+\s+(on|toward)\s+(.+)$', caseSensitive: false);

/// Rewrites a Directions API "Head (compass direction) on/toward X"
/// instruction (see [classifyTurnManeuver]) into one relative to the
/// traveler's own heading, e.g. "Turn left onto X" / "Continue on X" -
/// preserving whatever place/street name followed "on"/"toward". Falls
/// back to the original text unchanged if it doesn't match that expected
/// shape (a defensive fallback, not expected to trigger against the
/// English API responses this app requests).
String relabelHeadInstruction(String original, String? syntheticManeuver) {
  final match = _headInstructionPattern.firstMatch(original);
  if (match == null) return original;
  final preposition = match.group(1)!;
  final place = match.group(2)!;

  final String phrase;
  switch (syntheticManeuver) {
    case 'turn-left':
    case 'turn-sharp-left':
      phrase = 'Turn left';
    case 'turn-slight-left':
      phrase = 'Keep left';
    case 'turn-right':
    case 'turn-sharp-right':
      phrase = 'Turn right';
    case 'turn-slight-right':
      phrase = 'Keep right';
    case 'uturn-left':
    case 'uturn-right':
      phrase = 'Make a U-turn';
    default:
      phrase = 'Continue';
  }

  final connector = syntheticManeuver == null
      ? preposition
      : (preposition.toLowerCase() == 'on' ? 'onto' : preposition);
  return '$phrase $connector $place';
}

/// Maps a Directions API `maneuver` value (or one of [classifyTurnManeuver]'s
/// synthetic equivalents) to a navigation-style icon - falls back to a
/// plain straight-ahead arrow for steps with no maneuver at all.
IconData maneuverIcon(String? maneuver) {
  switch (maneuver) {
    case 'turn-left':
      return Icons.turn_left;
    case 'turn-right':
      return Icons.turn_right;
    case 'turn-slight-left':
      return Icons.turn_slight_left;
    case 'turn-slight-right':
      return Icons.turn_slight_right;
    case 'turn-sharp-left':
      return Icons.turn_sharp_left;
    case 'turn-sharp-right':
      return Icons.turn_sharp_right;
    case 'uturn-left':
      return Icons.u_turn_left;
    case 'uturn-right':
      return Icons.u_turn_right;
    case 'merge':
      return Icons.merge_type;
    case 'fork-left':
    case 'ramp-left':
    case 'keep-left':
      return Icons.fork_left;
    case 'fork-right':
    case 'ramp-right':
    case 'keep-right':
      return Icons.fork_right;
    case 'roundabout-left':
      return Icons.roundabout_left;
    case 'roundabout-right':
      return Icons.roundabout_right;
    case 'ferry':
    case 'ferry-train':
      return Icons.directions_boat;
    default:
      return Icons.straight;
  }
}
