import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/route_plan.dart';

void main() {
  group('RouteStop', () {
    test('round-trips through toMap/fromMap', () {
      final stop = RouteStop(lat: 37.4219, lng: -122.084);
      final restored = RouteStop.fromMap(stop.toMap());

      expect(restored.lat, stop.lat);
      expect(restored.lng, stop.lng);
    });

    test('fromMap accepts integer-valued coordinates (Firestore numbers)', () {
      final stop = RouteStop.fromMap({'lat': 37, 'lng': -122});
      expect(stop.lat, 37.0);
      expect(stop.lng, -122.0);
    });
  });

  group('RoutePlan', () {
    RoutePlan buildSample() => RoutePlan(
          origin: RouteStop(lat: 37.4219, lng: -122.084),
          destination: RouteStop(lat: 37.5483, lng: -121.9886),
          waypoints: [
            RouteStop(lat: 37.45, lng: -122.0),
            RouteStop(lat: 37.5, lng: -121.95),
          ],
          polyline: 'abc123',
          distanceMeters: 32186,
          durationSeconds: 1800,
        );

    test('fromMap round-trips origin, destination, and waypoints in order', () {
      final original = buildSample();
      final map = original.toMap();
      final restored = RoutePlan.fromMap(map);

      expect(restored.origin.lat, original.origin.lat);
      expect(restored.origin.lng, original.origin.lng);
      expect(restored.destination.lat, original.destination.lat);
      expect(restored.destination.lng, original.destination.lng);
      expect(restored.waypoints, hasLength(2));
      expect(restored.waypoints[0].lat, original.waypoints[0].lat);
      expect(restored.waypoints[1].lat, original.waypoints[1].lat);
      expect(restored.polyline, original.polyline);
      expect(restored.distanceMeters, original.distanceMeters);
      expect(restored.durationSeconds, original.durationSeconds);
    });

    test('fromMap defaults to no waypoints when the field is absent', () {
      final map = buildSample().toMap()..remove('waypoints');
      final restored = RoutePlan.fromMap(map);
      expect(restored.waypoints, isEmpty);
    });

    test('fromMap defaults distance/duration to 0 when absent', () {
      final map = buildSample().toMap()
        ..remove('distanceMeters')
        ..remove('durationSeconds');
      final restored = RoutePlan.fromMap(map);
      expect(restored.distanceMeters, 0);
      expect(restored.durationSeconds, 0);
    });
  });
}
