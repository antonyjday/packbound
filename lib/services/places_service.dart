import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/place_suggestion.dart';
import '../models/route_plan.dart';

/// Address search/autocomplete for SetRouteScreen, via the Places API
/// (New) - same Android-restricted Maps key already used for map tiles and
/// Directions (see DirectionsService), just also allow-listed for this API.
class PlacesService {
  static const _apiKey = 'AIzaSyAmylfZB3RZCB5TcIJ3g63nk_t2IKRiSX4';
  static const _androidPackage = 'net.packbound.app';
  static const _androidCertSha1 = 'EF3D285E4E29E32701475DFBED5B113403E47B68';

  /// A fresh token to group one search session's autocomplete keystrokes
  /// with its eventual place-details lookup - Google bills that whole
  /// session as a single unit rather than per-request as long as the same
  /// token is passed throughout. Callers should get a new one each time a
  /// search starts (e.g. when the search field goes from empty to
  /// non-empty) and discard it once a suggestion is resolved.
  String newSessionToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
    RouteStop? biasCenter,
  }) async {
    if (input.trim().isEmpty) return [];

    final response = await http.post(
      Uri.https('places.googleapis.com', '/v1/places:autocomplete'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Android-Package': _androidPackage,
        'X-Android-Cert': _androidCertSha1,
      },
      body: jsonEncode({
        'input': input,
        'sessionToken': sessionToken,
        // Soft bias, not a hard restriction - lets nearby results rank
        // first without blocking a search for somewhere further away.
        if (biasCenter != null)
          'locationBias': {
            'circle': {
              'center': {
                'latitude': biasCenter.lat,
                'longitude': biasCenter.lng,
              },
              'radius': 50000.0,
            },
          },
      }),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(
        'Place search failed: ${body['error']?['message'] ?? response.body}',
      );
    }

    final suggestions = body['suggestions'] as List<dynamic>? ?? [];
    return suggestions.map((raw) {
      final prediction = raw['placePrediction'] as Map<String, dynamic>;
      final structured = prediction['structuredFormat'] as Map<String, dynamic>?;
      final mainText = structured?['mainText']?['text'] as String?;
      final secondaryText = structured?['secondaryText']?['text'] as String?;
      return PlaceSuggestion(
        placeId: prediction['placeId'] as String,
        primaryText: mainText ?? (prediction['text']['text'] as String),
        secondaryText: secondaryText,
      );
    }).toList();
  }

  Future<RouteStop> resolvePlace(
    String placeId, {
    required String sessionToken,
  }) async {
    final response = await http.get(
      Uri.https(
        'places.googleapis.com',
        '/v1/places/$placeId',
        {'sessionToken': sessionToken},
      ),
      headers: {
        'X-Goog-Api-Key': _apiKey,
        'X-Android-Package': _androidPackage,
        'X-Android-Cert': _androidCertSha1,
        // Places API (New) returns no fields at all unless explicitly
        // asked for, to keep responses (and billing) minimal - we only
        // need the coordinates.
        'X-Goog-FieldMask': 'location',
      },
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(
        'Could not resolve place: ${body['error']?['message'] ?? response.body}',
      );
    }

    final location = body['location'] as Map<String, dynamic>;
    return RouteStop(
      lat: (location['latitude'] as num).toDouble(),
      lng: (location['longitude'] as num).toDouble(),
    );
  }
}
