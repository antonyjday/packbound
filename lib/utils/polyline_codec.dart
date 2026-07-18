import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes a Google-encoded polyline string (as returned by the Directions
/// API's `overview_polyline.points`) into a list of coordinates.
/// Standard algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    lat += _decodeSignedValue(encoded, index, (consumed) => index = consumed);
    lng += _decodeSignedValue(encoded, index, (consumed) => index = consumed);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }

  return points;
}

int _decodeSignedValue(String encoded, int start, void Function(int) advance) {
  int result = 0;
  int shift = 0;
  int index = start;
  int b;
  do {
    b = encoded.codeUnitAt(index++) - 63;
    result |= (b & 0x1f) << shift;
    shift += 5;
  } while (b >= 0x20);
  advance(index);
  return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
}
