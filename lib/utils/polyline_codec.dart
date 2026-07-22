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

/// Encodes coordinates into a Google polyline string - the reverse of
/// [decodePolyline]. Used by DirectionsService to rebuild a route's
/// polyline from its steps' own individual polylines concatenated
/// together, which are far more precise than the Directions API's single
/// "overview" polyline for the whole trip (deliberately simplified/
/// smoothed by Google - fine for a short hop, but visibly cuts corners
/// once zoomed in on a long multi-hundred-mile route).
String encodePolyline(List<LatLng> points) {
  final buffer = StringBuffer();
  int prevLat = 0;
  int prevLng = 0;

  for (final point in points) {
    final lat = (point.latitude * 1e5).round();
    final lng = (point.longitude * 1e5).round();
    _encodeSignedValue(lat - prevLat, buffer);
    _encodeSignedValue(lng - prevLng, buffer);
    prevLat = lat;
    prevLng = lng;
  }

  return buffer.toString();
}

void _encodeSignedValue(int value, StringBuffer buffer) {
  var signedValue = value << 1;
  if (value < 0) signedValue = ~signedValue;
  while (signedValue >= 0x20) {
    buffer.writeCharCode((0x20 | (signedValue & 0x1f)) + 63);
    signedValue >>= 5;
  }
  buffer.writeCharCode(signedValue + 63);
}
