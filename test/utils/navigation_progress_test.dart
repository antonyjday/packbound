import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/route_plan.dart';
import 'package:convoy_app/utils/navigation_progress.dart';

void main() {
  group('nextNavigationStep', () {
    RouteStep step(double endLat, double endLng) => RouteStep(
          instruction: 'Head north on Main St',
          maneuver: null,
          distanceMeters: 100,
          startLocation: RouteStop(lat: 0, lng: 0),
          endLocation: RouteStop(lat: endLat, lng: endLng),
        );

    final steps = [step(37.0, -122.0), step(37.1, -122.0), step(37.2, -122.0)];

    test('returns the first step when far from everything', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      expect(nextNavigationStep(farAway, steps), same(steps[0]));
    });

    test('advances once the current step\'s endpoint is reached', () {
      final atStep0 = RouteStop(lat: 37.0, lng: -122.0);
      expect(nextNavigationStep(atStep0, steps), same(steps[1]));
    });

    test('returns null once every step has been reached (arrived)', () {
      final atLastStep = RouteStop(lat: 37.2, lng: -122.0);
      expect(nextNavigationStep(atLastStep, steps), isNull);
    });

    test('returns null for an empty step list', () {
      expect(nextNavigationStep(RouteStop(lat: 0, lng: 0), []), isNull);
    });
  });

  group('classifyTurnManeuver', () {
    test('south heading turning to east is a left turn', () {
      // The example from the feature request: southbound (180), needing to
      // head east (90) next - a -90 degree (counter-clockwise) change.
      expect(classifyTurnManeuver(180, 90), 'turn-left');
    });

    test('south heading turning to west is a right turn', () {
      expect(classifyTurnManeuver(180, 270), 'turn-right');
    });

    test('continuing in roughly the same direction is null (straight)', () {
      expect(classifyTurnManeuver(90, 95), isNull);
      expect(classifyTurnManeuver(10, 358), isNull); // wraps past 0/360
    });

    test('a small deviation is a slight turn', () {
      expect(classifyTurnManeuver(0, 30), 'turn-slight-right');
      expect(classifyTurnManeuver(0, 330), 'turn-slight-left');
    });

    test('a near-reversal is a U-turn', () {
      expect(classifyTurnManeuver(0, 179), 'uturn-right');
      expect(classifyTurnManeuver(0, 181), 'uturn-left');
    });

    test('handles headings that wrap across 0/360', () {
      // 350 -> 80 is a +90 change the short way around (through 0), not the
      // 270-degree way around going backwards.
      expect(classifyTurnManeuver(350, 80), 'turn-right');
    });
  });

  group('relabelHeadInstruction', () {
    test('rewrites "Head <dir> on X" using "onto" for a turn', () {
      expect(
        relabelHeadInstruction('Head east on Main St', 'turn-left'),
        'Turn left onto Main St',
      );
    });

    test('rewrites "Head <dir> toward X" keeping "toward" for a turn', () {
      expect(
        relabelHeadInstruction('Head southeast toward Saville Cl', 'turn-left'),
        'Turn left toward Saville Cl',
      );
    });

    test('uses "Continue" with the original preposition when going straight', () {
      expect(
        relabelHeadInstruction('Head north on Elm St', null),
        'Continue on Elm St',
      );
    });

    test('leaves non-matching text unchanged', () {
      expect(
        relabelHeadInstruction('Merge onto I-5 N', 'turn-left'),
        'Merge onto I-5 N',
      );
    });
  });

  group('maneuverIcon', () {
    test('returns a straight-ahead icon for null (no maneuver)', () {
      expect(maneuverIcon(null), Icons.straight);
    });

    test('maps left/right turn variants to distinct icons', () {
      expect(maneuverIcon('turn-left'), Icons.turn_left);
      expect(maneuverIcon('turn-right'), Icons.turn_right);
      expect(maneuverIcon('turn-left'), isNot(maneuverIcon('turn-right')));
    });
  });
}
