import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/models/trip_type.dart';
import 'package:convoy_app/utils/quick_messages.dart';

void main() {
  group('quickMessagePresetsFor', () {
    test('returns a non-empty, distinct-text list for every trip type', () {
      for (final type in TripType.values) {
        final presets = quickMessagePresetsFor(type);
        expect(presets, isNotEmpty);
        expect(presets.map((p) => p.text).toSet().length, presets.length);
      }
    });

    test('presets differ between trip types (not one list for everything)', () {
      final car = quickMessagePresetsFor(TripType.car).map((p) => p.text).toSet();
      final walk = quickMessagePresetsFor(TripType.walk).map((p) => p.text).toSet();
      expect(car, isNot(equals(walk)));
      // Car-specific phrasing shouldn't leak into a walking trip.
      expect(walk.contains('Need fuel'), false);
    });
  });

  group('iconForQuickMessageText', () {
    test('finds the icon for a preset from any trip type', () {
      expect(iconForQuickMessageText('Need fuel'), isNotNull); // car
      expect(iconForQuickMessageText('Missed the train'), isNotNull); // train
      expect(iconForQuickMessageText('Flat tire'), isNotNull); // bicycle
    });

    test('returns null for free text that matches no preset', () {
      expect(iconForQuickMessageText('not a real preset'), isNull);
    });
  });
}
