import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/trip_type.dart';

void main() {
  group('TripType.fromName', () {
    test('round-trips every value through its own name', () {
      for (final type in TripType.values) {
        expect(TripType.fromName(type.name), type);
      }
    });

    test('falls back to car for an unrecognized or missing name', () {
      expect(TripType.fromName('spaceship'), TripType.car);
      expect(TripType.fromName(null), TripType.car);
    });
  });

  group('TripType.directionsMode', () {
    test('maps to the expected Google Directions API mode string', () {
      expect(TripType.car.directionsMode, 'driving');
      expect(TripType.train.directionsMode, 'transit');
      expect(TripType.bicycle.directionsMode, 'bicycling');
      expect(TripType.walk.directionsMode, 'walking');
    });
  });

  group('TripType.nearbyZoom', () {
    test('zooms in further for slower/shorter-range trip types', () {
      // Walking's plausible range is the smallest, so it should be the most
      // zoomed in; a car covers the most ground, so the least zoomed in.
      expect(TripType.walk.nearbyZoom, greaterThan(TripType.bicycle.nearbyZoom));
      expect(TripType.bicycle.nearbyZoom, greaterThan(TripType.car.nearbyZoom));
      expect(TripType.car.nearbyZoom, greaterThan(TripType.train.nearbyZoom));
    });
  });

  group('TripType.movingSpeedThresholdMps', () {
    test('is lowest for walk, since typical walking pace is slowest', () {
      expect(
        TripType.walk.movingSpeedThresholdMps,
        lessThan(TripType.bicycle.movingSpeedThresholdMps),
      );
      expect(
        TripType.bicycle.movingSpeedThresholdMps,
        lessThan(TripType.car.movingSpeedThresholdMps),
      );
    });

    test('is below typical walking pace, so walk trips clear it', () {
      const typicalWalkingSpeedMps = 1.3;
      expect(
        TripType.walk.movingSpeedThresholdMps,
        lessThan(typicalWalkingSpeedMps),
      );
    });

    test('car and train share the same threshold', () {
      expect(
        TripType.car.movingSpeedThresholdMps,
        TripType.train.movingSpeedThresholdMps,
      );
    });
  });
}
