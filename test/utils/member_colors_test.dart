import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:convoy_app/utils/member_colors.dart';

void main() {
  group('markerHueForUser', () {
    test('is deterministic for the same uid', () {
      const uid = 'user-abc-123';
      expect(markerHueForUser(uid), markerHueForUser(uid));
    });

    test('never returns hueViolet or hueAzure - reserved for route markers',
        () {
      // A spread of arbitrary uids, enough to be confident the palette
      // (checked here indirectly, since it's private to member_colors.dart)
      // doesn't include either reserved hue for any input.
      final uids = List.generate(50, (i) => 'user-$i');
      for (final uid in uids) {
        final hue = markerHueForUser(uid);
        expect(hue, isNot(BitmapDescriptor.hueViolet));
        expect(hue, isNot(BitmapDescriptor.hueAzure));
      }
    });

    test('produces more than one distinct color across different uids', () {
      final uids = List.generate(50, (i) => 'user-$i');
      final hues = uids.map(markerHueForUser).toSet();
      expect(hues.length, greaterThan(1));
    });
  });

  group('colorForMarkerHue', () {
    test('returns a fully opaque color', () {
      final color = colorForMarkerHue(BitmapDescriptor.hueRed);
      expect(color.a, 1.0);
    });

    test('different hues produce different colors', () {
      final red = colorForMarkerHue(BitmapDescriptor.hueRed);
      final green = colorForMarkerHue(BitmapDescriptor.hueGreen);
      expect(red, isNot(green));
    });
  });
}
