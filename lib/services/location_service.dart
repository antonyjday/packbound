import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_point.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionSub;

  /// Checks current permission status WITHOUT triggering an OS prompt.
  /// Use this to decide whether to show an explainer before asking.
  Future<LocationPermission> checkPermissionStatus() {
    return Geolocator.checkPermission();
  }

  /// Requests OS-level location permission. Call before starting to share.
  /// Two-step request: first "while in use", then escalate to "always" so
  /// sharing keeps working while the app is minimized during a drive.
  Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;

    // Escalate to "always" for background updates. On iOS this shows a
    // second system prompt after the first one is granted; on Android
    // it maps to the separate background-location permission (API 29+).
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    return serviceEnabled &&
        (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse);
  }

  LocationSettings _platformSettings(int distanceFilterMeters) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        intervalDuration: const Duration(seconds: 3),
        // Keeps location updates alive when the app is backgrounded by
        // running as a foreground service with a persistent notification -
        // required on Android 9+ for reliable background tracking.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Convoy is sharing your location',
          notificationText: 'Your travel group can see your position',
          enableWakeLock: true,
        ),
      );
    } else if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        // Keeps delivering updates after the app is backgrounded/suspended
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
  }

  /// Starts pushing this device's position to
  /// groups/{groupId}/locations/{userId} on every significant movement.
  /// distanceFilter controls update frequency vs. battery use.
  Future<void> startSharing({
    required String groupId,
    required String userId,
    required String displayName,
    int distanceFilterMeters = 10,
  }) async {
    final ok = await ensurePermission();
    if (!ok) {
      throw Exception('Location permission not granted');
    }

    final settings = _platformSettings(distanceFilterMeters);

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position pos) {
        final point = LocationPoint(
          userId: userId,
          displayName: displayName,
          lat: pos.latitude,
          lng: pos.longitude,
          heading: pos.heading,
          speed: pos.speed,
          updatedAt: Timestamp.now(),
        );

        _db
            .collection('groups')
            .doc(groupId)
            .collection('locations')
            .doc(userId)
            .set(point.toMap(), SetOptions(merge: true));
      },
    );
  }

  Future<void> stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  /// Live stream of every member's location within a group.
  Stream<List<LocationPoint>> groupLocationsStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('locations')
        .snapshots()
        .map((snap) => snap.docs.map(LocationPoint.fromDoc).toList());
  }
}
