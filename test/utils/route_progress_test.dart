import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:convoy_app/models/route_plan.dart';
import 'package:convoy_app/utils/route_progress.dart';

void main() {
  // A start point plus two waypoints, spaced well apart so "near" vs "far"
  // is unambiguous at the default 500m arrival radius.
  final start = RouteStop(lat: 37.0, lng: -122.0);
  final waypoint1 = RouteStop(lat: 37.1, lng: -122.0);
  final waypoint2 = RouteStop(lat: 37.2, lng: -122.0);
  final destination = RouteStop(lat: 37.3, lng: -122.0);

  RoutePlan buildRoute() => RoutePlan(
        origin: start,
        destination: destination,
        waypoints: [waypoint1, waypoint2],
        polyline: '',
        distanceMeters: 0,
        durationSeconds: 0,
      );

  group('remainingLegs', () {
    test('returns every leg when far from all of them', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final legs = remainingLegs(farAway, buildRoute());
      expect(legs, [start, waypoint1, waypoint2]);
    });

    test('drops the start point once reached, keeping waypoint order', () {
      final legs = remainingLegs(start, buildRoute());
      expect(legs, [waypoint1, waypoint2]);
    });

    test('drops legs in order as each is reached', () {
      final legs = remainingLegs(waypoint1, buildRoute());
      expect(legs, [waypoint2]);
    });

    test('returns an empty list once every leg is reached', () {
      final legs = remainingLegs(waypoint2, buildRoute());
      expect(legs, isEmpty);
    });

    test('treats a leg exactly at the arrival radius as reached (inclusive)', () {
      final exactDistance =
          Geolocator.distanceBetween(start.lat, start.lng, waypoint1.lat, waypoint1.lng);
      final legs = remainingLegs(
        start,
        buildRoute(),
        arrivalRadiusMeters: exactDistance,
      );
      // At exactly the radius, waypoint1 counts as reached too (not just
      // the start point), since the boundary check is strictly "further
      // than" the radius.
      expect(legs, [waypoint2]);
    });

    test('manualSkipCount forces legs to count as passed regardless of proximity', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final legs = remainingLegs(farAway, buildRoute(), manualSkipCount: 2);
      expect(legs, [waypoint2]);
    });

    test('manualSkipCount of 0 or less has no effect beyond proximity', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final legs = remainingLegs(farAway, buildRoute(), manualSkipCount: 0);
      expect(legs, [start, waypoint1, waypoint2]);
    });

    test('manualSkipCount is clamped to the number of legs, never overshoots', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final legs = remainingLegs(farAway, buildRoute(), manualSkipCount: 99);
      expect(legs, isEmpty);
    });

    test('proximity and manualSkipCount combine as whichever passed more legs', () {
      // Physically at waypoint1 (2 legs reached by proximity), but only
      // manually skipped 1 - proximity should win.
      final legsA = remainingLegs(waypoint1, buildRoute(), manualSkipCount: 1);
      expect(legsA, [waypoint2]);

      // Physically still far from everything (0 legs reached by
      // proximity), but manually skipped 2 - the manual skip should win.
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final legsB = remainingLegs(farAway, buildRoute(), manualSkipCount: 2);
      expect(legsB, [waypoint2]);
    });

    test('handles a route with no waypoints - just the start point', () {
      final route = RoutePlan(
        origin: start,
        destination: destination,
        waypoints: const [],
        polyline: '',
        distanceMeters: 0,
        durationSeconds: 0,
      );
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      expect(remainingLegs(farAway, route), [start]);
      expect(remainingLegs(start, route), isEmpty);
    });
  });
}
