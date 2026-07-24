import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/route_plan.dart';
import '../utils/polyline_codec.dart';

/// The Directions API flatly does not support the waypoints parameter for
/// transit directions (a train trip) - it returns INVALID_REQUEST if both
/// are present. Rather than fail the whole route, [DirectionsService.route]
/// silently routes origin-to-destination only for transit; waypoints still
/// apply for every other mode. A standalone top-level function so this
/// exact rule is unit-testable without a live network call.
List<RouteStop> waypointsForMode(String mode, List<RouteStop> waypoints) =>
    mode == 'transit' ? const <RouteStop>[] : waypoints;

/// Calls the (legacy) Directions API to turn an origin/destination/ordered
/// waypoints into an actual route for the group's trip type (see
/// trip_type.dart's directionsMode). Used once, on the setting device, when
/// a route is saved or amended - every viewer just renders the stored
/// result, no per-viewer API calls for the route itself (see DirectionsService
/// usage in MapScreen for the separate, throttled "my live ETA" calls).
class DirectionsService {
  // Same Android-restricted Maps key already used for the map tiles
  // (android/app/src/main/AndroidManifest.xml) - also allow-listed for the
  // Directions API, so the same key works for both.
  static const _apiKey = 'AIzaSyC1AvTuEWbVH0aELNYfPXdwncynWnGFCI0';
  static const _androidPackage = 'net.packbound.app';
  static const _androidCertSha1 = 'CD1AC77CA5CBAF0D6D8DEFA83CEB4D7DA999C289';

  Future<RoutePlan> route({
    required RouteStop origin,
    required RouteStop destination,
    required List<RouteStop> waypoints,
    String mode = 'driving',
  }) async {
    final effectiveWaypoints = waypointsForMode(mode, waypoints);
    final params = {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'key': _apiKey,
      'mode': mode,
      if (effectiveWaypoints.isNotEmpty)
        // No "via:" prefix - these are real intended stops the group plans to
        // actually stop at, not just route-shaping hints.
        'waypoints': effectiveWaypoints.map((w) => '${w.lat},${w.lng}').join('|'),
    };
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', params);

    // Android-restricted API keys are enforced on the Maps SDK automatically,
    // but a raw REST call like this needs to identify itself with these two
    // headers for Google to honor the same key's Android app restriction.
    final response = await http.get(uri, headers: {
      'X-Android-Package': _androidPackage,
      'X-Android-Cert': _androidCertSha1,
    });

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'OK') {
      throw Exception(
        'Could not calculate route: ${body['status']}'
        '${body['error_message'] != null ? ' - ${body['error_message']}' : ''}',
      );
    }

    final route = (body['routes'] as List).first as Map<String, dynamic>;
    final legs = route['legs'] as List;
    int distanceMeters = 0;
    int durationSeconds = 0;
    final steps = <RouteStep>[];
    // Built from each step's own polyline rather than the response's
    // overview_polyline - see encodePolyline's doc comment for why.
    final precisePoints = <LatLng>[];
    for (final leg in legs) {
      distanceMeters += (leg['distance']['value'] as num).toInt();
      durationSeconds += (leg['duration']['value'] as num).toInt();
      for (final step in leg['steps'] as List) {
        final start = step['start_location'] as Map<String, dynamic>;
        final end = step['end_location'] as Map<String, dynamic>;
        steps.add(RouteStep(
          instruction: _stripHtml(step['html_instructions'] as String),
          maneuver: step['maneuver'] as String?,
          distanceMeters: (step['distance']['value'] as num).toInt(),
          startLocation: RouteStop(
            lat: (start['lat'] as num).toDouble(),
            lng: (start['lng'] as num).toDouble(),
          ),
          endLocation: RouteStop(
            lat: (end['lat'] as num).toDouble(),
            lng: (end['lng'] as num).toDouble(),
          ),
        ));
        precisePoints.addAll(decodePolyline(step['polyline']['points'] as String));
      }
    }

    return RoutePlan(
      origin: origin,
      destination: destination,
      // Reflects what was actually routed through, not what was asked for -
      // see effectiveWaypoints above, transit silently drops these.
      waypoints: effectiveWaypoints,
      polyline: encodePolyline(precisePoints),
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      steps: steps,
    );
  }

  // The legacy Directions API's html_instructions are simple markup (mostly
  // <b> around street names, occasionally a <div> for a "toward X" aside) -
  // strip tags and the handful of entities Google actually emits, rather
  // than pulling in a full HTML parser for this.
  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
