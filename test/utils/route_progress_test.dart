import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  group('remainingWaypoints', () {
    test('returns every waypoint when far from all of them', () {
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      expect(remainingWaypoints(farAway, [waypoint1, waypoint2]), [waypoint1, waypoint2]);
    });

    test('drops waypoints in order as each is reached', () {
      expect(remainingWaypoints(waypoint1, [waypoint1, waypoint2]), [waypoint2]);
    });

    test('returns an empty list once every waypoint is reached', () {
      expect(remainingWaypoints(waypoint2, [waypoint1, waypoint2]), isEmpty);
    });

    test('never treats the start point as a waypoint to drop', () {
      // Being at `start` shouldn't affect a waypoint list that doesn't
      // include it - unlike remainingLegs, there's no start-point leg here.
      expect(remainingWaypoints(start, [waypoint1, waypoint2]), [waypoint1, waypoint2]);
    });

    test('uses a tighter default radius than remainingLegs', () {
      // Comfortably inside remainingLegs' 500m default but outside
      // remainingWaypoints' 100m default - only remainingLegs should treat
      // it as reached.
      final justOutsideClearRadius = RouteStop(
        lat: waypoint1.lat + 0.002, // ~222m north of waypoint1
        lng: waypoint1.lng,
      );
      expect(remainingWaypoints(justOutsideClearRadius, [waypoint1, waypoint2]),
          [waypoint1, waypoint2]);
      // remainingLegs' default 500m radius does reach waypoint1 from here
      // (and, transitively, the start point too, since "last reached"
      // proximity doesn't require having actually passed through it) -
      // only waypoint2 remains.
      expect(remainingLegs(justOutsideClearRadius, buildRoute()), [waypoint2]);
    });
  });

  group('distanceFromRouteMeters', () {
    test('returns 0 (or near enough) when standing on a route point', () {
      final routePoints = [
        LatLng(start.lat, start.lng),
        LatLng(waypoint1.lat, waypoint1.lng),
      ];
      expect(distanceFromRouteMeters(start, routePoints), lessThan(1));
    });

    test('returns the distance to the nearest point when off the route', () {
      final routePoints = [
        LatLng(start.lat, start.lng),
        LatLng(waypoint1.lat, waypoint1.lng),
      ];
      final farAway = RouteStop(lat: 10.0, lng: 10.0);
      final expected = Geolocator.distanceBetween(
        farAway.lat, farAway.lng, waypoint1.lat, waypoint1.lng,
      );
      expect(distanceFromRouteMeters(farAway, routePoints), closeTo(expected, 1));
    });

    test('returns infinity for an empty route', () {
      expect(distanceFromRouteMeters(start, const []), double.infinity);
    });
  });
}
