import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/route_plan.dart';
import 'package:convoy_app/services/directions_service.dart';

void main() {
  group('waypointsForMode', () {
    final waypoints = [
      RouteStop(lat: 1, lng: 2),
      RouteStop(lat: 3, lng: 4),
    ];

    test('drops all waypoints for transit', () {
      expect(waypointsForMode('transit', waypoints), isEmpty);
    });

    test('keeps waypoints for driving, bicycling, and walking', () {
      for (final mode in ['driving', 'bicycling', 'walking']) {
        expect(waypointsForMode(mode, waypoints), waypoints);
      }
    });

    test('is a no-op when there are no waypoints to begin with', () {
      expect(waypointsForMode('transit', const []), isEmpty);
      expect(waypointsForMode('driving', const []), isEmpty);
    });
  });
}
