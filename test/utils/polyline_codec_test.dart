import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:convoy_app/utils/polyline_codec.dart';

void main() {
  group('decodePolyline', () {
    test('decodes an empty string to an empty list', () {
      expect(decodePolyline(''), isEmpty);
    });

    test("decodes Google's canonical example polyline", () {
      // From Google's own encoded polyline algorithm docs:
      // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 1e-5));
      expect(points[0].longitude, closeTo(-120.2, 1e-5));
      expect(points[1].latitude, closeTo(40.7, 1e-5));
      expect(points[1].longitude, closeTo(-120.95, 1e-5));
      expect(points[2].latitude, closeTo(43.252, 1e-5));
      expect(points[2].longitude, closeTo(-126.453, 1e-5));
    });
  });

  group('encodePolyline', () {
    test('encodes an empty list to an empty string', () {
      expect(encodePolyline([]), isEmpty);
    });

    test("encodes Google's canonical example polyline", () {
      final points = [
        const LatLng(38.5, -120.2),
        const LatLng(40.7, -120.95),
        const LatLng(43.252, -126.453),
      ];
      expect(encodePolyline(points), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    });

    test('round-trips through decodePolyline unchanged', () {
      final original = [
        const LatLng(51.5074, -0.1278),
        const LatLng(52.4862, -1.8904),
        const LatLng(53.4808, -2.2426),
      ];

      final roundTripped = decodePolyline(encodePolyline(original));

      expect(roundTripped, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(roundTripped[i].latitude, closeTo(original[i].latitude, 1e-5));
        expect(roundTripped[i].longitude, closeTo(original[i].longitude, 1e-5));
      }
    });
  });
}
