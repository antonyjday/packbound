import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/route_plan.dart';

/// Calls the (legacy) Directions API to turn an origin/destination/ordered
/// waypoints into an actual driving route. Used once, on the setting device,
/// when a route is saved or amended - every viewer just renders the stored
/// result, no per-viewer API calls for the route itself (see DirectionsService
/// usage in MapScreen for the separate, throttled "my live ETA" calls).
class DirectionsService {
  // Same Android-restricted Maps key already used for the map tiles
  // (android/app/src/main/AndroidManifest.xml) - also allow-listed for the
  // Directions API, so the same key works for both.
  static const _apiKey = 'AIzaSyAmylfZB3RZCB5TcIJ3g63nk_t2IKRiSX4';
  static const _androidPackage = 'com.example.convoy.convoy_app';
  static const _androidCertSha1 = 'EF3D285E4E29E32701475DFBED5B113403E47B68';

  Future<RoutePlan> route({
    required RouteStop origin,
    required RouteStop destination,
    required List<RouteStop> waypoints,
  }) async {
    final params = {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'key': _apiKey,
      if (waypoints.isNotEmpty)
        // No "via:" prefix - these are real intended stops the group plans to
        // actually stop at, not just route-shaping hints.
        'waypoints': waypoints.map((w) => '${w.lat},${w.lng}').join('|'),
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
    for (final leg in legs) {
      distanceMeters += (leg['distance']['value'] as num).toInt();
      durationSeconds += (leg['duration']['value'] as num).toInt();
    }

    return RoutePlan(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
      polyline: route['overview_polyline']['points'],
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }
}
