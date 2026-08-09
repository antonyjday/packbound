import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_point.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;
  Position? _lastPosition;

  /// How often to re-send the last known position even without movement.
  /// distanceFilter means a stationary device produces no position-stream
  /// events at all, so without this a member standing still for over a
  /// minute would flip to SignalStatus.lost (see LocationPoint.status) -
  /// looking to everyone else like their signal actually dropped, when
  /// they're still right there. Comfortably under both that 60s cutoff
  /// and the server-side notifyLostSignals sweep's 5-minute one.
  static const _heartbeatInterval = Duration(seconds: 20);

  /// How long [_publishFirstFix] waits for a real fix before giving up and
  /// leaving it to the position stream. Generous because this is the "cold
  /// GPS in a car park" case it exists to cover, and nothing is blocked on
  /// it - it runs unawaited alongside the stream.
  static const _firstFixTimeout = Duration(seconds: 45);

  /// Checks current permission status WITHOUT triggering an OS prompt.
  /// Use this to decide whether to show an explainer before asking.
  Future<LocationPermission> checkPermissionStatus() {
    return Geolocator.checkPermission();
  }

  /// One-off position fetch (distinct from the continuous stream started by
  /// `startSharing`) - used e.g. as the origin when the owner sets a route.
  /// Assumes permission has already been granted (call `ensurePermission()`
  /// first).
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
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
        intervalDuration: const Duration(seconds: 6),
        // Keeps location updates alive when the app is backgrounded by
        // running as a foreground service with a persistent notification -
        // required on Android 9+ for reliable background tracking.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Packbound is sharing your location',
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
  /// distanceFilter controls update frequency vs. battery use - it also
  /// directly drives Firestore billing, since every write here is read by
  /// every other member's live listener (cost scales as writes * (members
  /// - 1)), so this is deliberately looser than "as live as possible".
  Future<void> startSharing({
    required String groupId,
    required String userId,
    required String displayName,
    int distanceFilterMeters = 25,
  }) async {
    final ok = await ensurePermission();
    if (!ok) {
      throw Exception('Location permission not granted');
    }

    final settings = _platformSettings(distanceFilterMeters);

    void writePosition(Position pos) {
      _lastPosition = pos;
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
          // Swallowed rather than left to become an unhandled async error:
          // a failed write here (offline, or the trip ended out from under
          // us) isn't independently actionable, and MapScreen already
          // notices the resulting absence from the locations feed - see its
          // "not visible to the group" banner.
          .set(point.toMap(), SetOptions(merge: true))
          .catchError((_) {});
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(writePosition);

    unawaited(_publishFirstFix(writePosition));

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final last = _lastPosition;
      if (last != null) writePosition(last);
    });
  }

  /// Publishes a position immediately on starting to share, instead of
  /// waiting for the position stream's first event.
  ///
  /// distanceFilter means the stream only emits once the device has *moved*
  /// that far, so someone who joins a trip while parked - or waiting at the
  /// meeting point, which is exactly when people join - can produce no
  /// stream event for a long time. Their location doc then never gets
  /// created at all, and since both the map markers and the roster are
  /// built from that feed, they're completely invisible to the group (and
  /// see everyone else just fine, since reading is unaffected) despite
  /// having correctly granted permission. The heartbeat timer doesn't cover
  /// this either: it re-sends [_lastPosition], which is still null until
  /// that first event.
  ///
  /// Tries the OS's cached fix first so the marker appears instantly, then
  /// a real one, since the cached fix can be minutes old and some distance
  /// away.
  Future<void> _publishFirstFix(void Function(Position) writePosition) async {
    Position? cached;
    try {
      cached = await Geolocator.getLastKnownPosition();
    } catch (_) {
      cached = null;
    }
    // Bail if sharing was stopped while awaiting, so a late seed can't
    // resurrect a marker the user has deliberately switched off.
    if (_positionSub == null) return;
    if (cached != null && _lastPosition == null) writePosition(cached);

    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _firstFixTimeout,
        ),
      );
      if (_positionSub == null) return;
      final last = _lastPosition;
      // The stream may have delivered something newer while this was in
      // flight - don't walk the position backwards if so.
      if (last == null || fresh.timestamp.isAfter(last.timestamp)) {
        writePosition(fresh);
      }
    } catch (_) {
      // No fix within the time limit (indoors, underground car park, cold
      // GPS). The position stream is still running and will publish as soon
      // as one arrives, so there's nothing to retry here.
    }
  }

  Future<void> stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastPosition = null;
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
