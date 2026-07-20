import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:convoy_app/utils/member_colors.dart';

void main() {
  group('markerHuesForUsers', () {
    test('is deterministic for the same set of uids', () {
      final uids = ['user-a', 'user-b', 'user-c'];
      expect(markerHuesForUsers(uids), markerHuesForUsers(uids));
    });

    test('does not depend on the input order', () {
      final uids = ['user-a', 'user-b', 'user-c'];
      final reversed = uids.reversed.toList();
      expect(markerHuesForUsers(uids), markerHuesForUsers(reversed));
    });

    test('assigns every user a distinct hue when the group fits the palette',
        () {
      // Regression coverage: a previous per-uid-hash approach could - and in
      // practice did, even with just 3 members - collide two different
      // users onto the same hue.
      final uids = List.generate(7, (i) => 'user-$i');
      final hues = markerHuesForUsers(uids).values.toSet();
      expect(hues.length, 7);
    });

    test('never assigns hueViolet, hueAzure, or hueGreen - reserved for route markers',
        () {
      // A spread of arbitrary uids, enough to be confident the palette
      // (checked here indirectly, since it's private to member_colors.dart)
      // doesn't include any reserved hue for any input.
      final uids = List.generate(50, (i) => 'user-$i');
      for (final hue in markerHuesForUsers(uids).values) {
        expect(hue, isNot(BitmapDescriptor.hueViolet));
        expect(hue, isNot(BitmapDescriptor.hueAzure));
        expect(hue, isNot(BitmapDescriptor.hueGreen));
      }
    });

    test('produces more than one distinct color across different uids', () {
      final uids = List.generate(50, (i) => 'user-$i');
      final hues = markerHuesForUsers(uids).values.toSet();
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
