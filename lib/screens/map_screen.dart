import 'dart:async';
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';
import '../models/location_point.dart';
import '../models/route_plan.dart';
import '../services/auth_service.dart';
import '../services/directions_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../utils/member_colors.dart';
import '../utils/polyline_codec.dart';
import 'location_permission_screen.dart';
import 'invite_screen.dart';
import 'set_route_screen.dart';
import '../widgets/convoy_status_list.dart';

class MapScreen extends StatefulWidget {
  final ConvoyGroup group;
  const MapScreen({super.key, required this.group});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _locationService = LocationService();
  final _groupService = GroupService();
  final _authService = AuthService();
  final _directionsService = DirectionsService();
  bool _sharing = false;
  bool _isOwner = false;
  GoogleMapController? _mapController;

  // The group's shared trip plan, synced live from the group doc (same
  // listener as trip-expiry below). Null if the owner hasn't set one.
  RoutePlan? _route;

  // This viewer's own live progress toward the route's destination -
  // separate from the route's static distance/duration, and recalculated
  // (throttled) as this device moves. See _maybeRecalculateMyEta.
  double? _myEtaDistanceMeters;
  Duration? _myEtaDuration;
  int _myEtaRemainingStops = 0;

  // The driving route from *this device's* current position to the
  // destination (via whichever waypoints it hasn't reached yet) - decoded
  // from the same throttled Directions call as the ETA above, so drawing it
  // costs nothing extra. Shown alongside the shared plan's static polyline
  // so each viewer sees their own remaining path, not just the route as it
  // looked from the owner's position when they set it.
  String? _myRoutePolyline;
  bool _etaCalcInFlight = false;
  DateTime? _lastEtaCalcAt;
  RouteStop? _lastEtaCalcPosition;

  // How close to a waypoint counts as "arrived" for the purposes of the
  // live ETA - waypoints within this radius are treated as already passed
  // and routed past, rather than back through, on the next recalculation.
  static const _waypointArrivalRadiusMeters = 500.0;

  // Forces a rebuild every few seconds so each marker's "seconds since
  // update" (and therefore its live/weak/lost status) stays current even
  // when no new Firestore data has arrived - staleness is a function of
  // wall-clock time, not of new events.
  Timer? _staleTicker;

  // Remembers each member's last known status so we can detect
  // transitions (live -> lost, lost -> live) and surface a toast,
  // instead of re-notifying on every rebuild.
  final Map<String, SignalStatus> _lastKnownStatus = {};

  bool _deviceOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Only auto-fit the camera once, the first time markers appear.
  // After that the user may have panned/zoomed manually and we shouldn't
  // yank the camera out from under them on every location update.
  bool _hasAutoFitted = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupStatusSub;
  bool _groupEnded = false;

  // Hard-cap expiry, kept in sync from the group doc listener so the
  // countdown/warning banner reflects extensions immediately.
  Timestamp? _tripExpiresAt;

  // Owner-controlled; false hides the share/invite button for non-owners.
  // Seeded from widget.group so it's correct before the first group-doc
  // snapshot arrives, then kept live from the listener below.
  bool _membersCanInvite = true;

  // Banner is dismissible, but reappears if the severity level goes up
  // (e.g. dismissed the 4h-out warning, but the 1h-out one still shows).
  int _dismissedWarningLevel = 0;

  static const earlyWarningLead = Duration(hours: 4);
  static const finalWarningLead = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _membersCanInvite = widget.group.membersCanInvite;
    _staleTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final offline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (offline != _deviceOffline && mounted) {
        setState(() => _deviceOffline = offline);
      }
    });

    // The trip can end two ways: the owner taps "end trip", or the
    // cleanup Cloud Function auto-ends it after a period of inactivity.
    // Either way, stop sharing immediately rather than waiting for the
    // security rule to reject the next write.
    _groupStatusSub = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.group.id)
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      final status = data?['status'];

      final newExpiry = data?['tripExpiresAt'] as Timestamp?;
      if (newExpiry != _tripExpiresAt && mounted) {
        setState(() => _tripExpiresAt = newExpiry);
      }

      final routeData = data?['route'];
      final newRoute = routeData != null
          ? RoutePlan.fromMap(Map<String, dynamic>.from(routeData))
          : null;
      // Compare by polyline rather than object identity - a fresh RoutePlan
      // is parsed on every snapshot even when nothing routing-related
      // changed, and resetting the live ETA on every unrelated group-doc
      // update (e.g. trip-expiry ticking) would make it flicker pointlessly.
      if (newRoute?.polyline != _route?.polyline && mounted) {
        setState(() {
          _route = newRoute;
          _myEtaDistanceMeters = null;
          _myEtaDuration = null;
          _myEtaRemainingStops = 0;
          _myRoutePolyline = null;
          _lastEtaCalcAt = null;
          _lastEtaCalcPosition = null;
        });
      }

      final newMembersCanInvite = data?['membersCanInvite'] ?? true;
      if (newMembersCanInvite != _membersCanInvite && mounted) {
        setState(() => _membersCanInvite = newMembersCanInvite);
      }

      if (status == 'ended' && !_groupEnded) {
        _groupEnded = true;
        await _locationService.stopSharing();
        if (mounted) {
          setState(() => _sharing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This trip has ended. Location sharing has stopped.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    });

    _checkOwnership();

    // Sharing defaults to on: most people opening a group's map are here to
    // be tracked, and re-tapping "start sharing" every time you reopen the
    // screen (sharing state isn't persisted - see stopSharing() in dispose())
    // is just friction. Goes through the exact same _toggleSharing path as
    // the manual button, so the permission explainer/prompts and error
    // handling for a first-time or denied user are unchanged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_sharing) _toggleSharing();
    });
  }

  Duration? get _timeUntilExpiry {
    if (_tripExpiresAt == null) return null;
    return _tripExpiresAt!.toDate().difference(DateTime.now());
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'any moment now';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  Future<void> _extendTrip() async {
    try {
      await _groupService.extendTrip(widget.group.id);
      setState(() => _dismissedWarningLevel = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip extended by another 24 hours')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Couldn\'t extend trip: $e')));
      }
    }
  }

  /// Banner shown when the hard-cap deadline is getting close. The owner
  /// gets an inline "Extend" button; other members get the same heads-up
  /// text but are told to ask the owner, since only the owner can extend.
  /// This is exactly the scenario called out by design: a convoy that
  /// stops driving for the night should see this *before* the 24h cap
  /// would breach overnight, so the owner can extend ahead of time.
  Widget? _buildExpiryBanner() {
    if (_groupEnded) return null;
    final remaining = _timeUntilExpiry;
    if (remaining == null) return null;

    final int level;
    if (remaining <= finalWarningLead) {
      level = 2;
    } else if (remaining <= earlyWarningLead) {
      level = 1;
    } else {
      return null;
    }

    if (level <= _dismissedWarningLevel) return null;

    final urgent = level == 2;
    final label = _formatDuration(remaining);

    return Container(
      width: double.infinity,
      color: urgent ? Colors.red.shade700 : Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Icon(urgent ? Icons.warning_amber : Icons.access_time,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isOwner
                  ? 'Trip ends in $label. Extend it now if the convoy isn\'t done yet.'
                  : 'Trip ends in $label. Ask the owner to extend if you\'re not done.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          if (_isOwner)
            TextButton(
              onPressed: _extendTrip,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: urgent ? Colors.red.shade700 : Colors.orange.shade800,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Extend 24h'),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () => setState(() => _dismissedWarningLevel = level),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _checkOwnership() async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.group.id)
        .collection('members')
        .doc(_authService.uid)
        .get();
    if (mounted) {
      setState(() => _isOwner = doc.data()?['role'] == 'owner');
    }
  }

  Future<void> _confirmEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this trip?'),
        content: const Text(
          'Everyone in the group will stop sharing their location and the '
          'trip will be marked as ended. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End trip'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _groupService.endGroup(widget.group.id);
      // The Firestore listener in initState picks up the status change
      // and handles stopping local sharing + showing the confirmation snackbar.
    }
  }

  Future<void> _openSetRoute() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetRouteScreen(group: widget.group, initialRoute: _route),
      ),
    );
  }

  Future<void> _clearRoute() async {
    try {
      await _groupService.clearRoute(widget.group.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleMembersCanInvite() async {
    final next = !_membersCanInvite;
    setState(() => _membersCanInvite = next); // optimistic; listener reconciles
    try {
      await _groupService.setMembersCanInvite(widget.group.id, next);
    } catch (e) {
      if (mounted) {
        setState(() => _membersCanInvite = !next);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _formatDistanceDuration(int meters, int seconds) {
    final miles = meters / 1609.34;
    final mins = (seconds / 60).round();
    final h = mins ~/ 60;
    final m = mins % 60;
    final timeLabel = h > 0 ? '${h}h ${m}m' : '${m}m';
    return '${miles.toStringAsFixed(1)} mi · $timeLabel';
  }

  /// Recomputes *this device's* live distance/ETA to the route's
  /// destination. Deliberately throttled - both at most once every 2
  /// minutes AND only once the device has moved 300m+ since the last calc -
  /// an unthrottled per-location-tick (every ~3s) recalculation would
  /// multiply Directions API billing for no real benefit. Scoped to my own
  /// progress only, not a live ETA for every member shown to everyone,
  /// which would multiply calls by member count.
  void _maybeRecalculateMyEta(List<LocationPoint> points) {
    if (_route == null || _etaCalcInFlight) return;

    final mine = points.where((p) => p.userId == _authService.uid);
    if (mine.isEmpty) return;
    final myPoint = mine.first;

    final now = DateTime.now();
    final dueByTime = _lastEtaCalcAt == null ||
        now.difference(_lastEtaCalcAt!) >= const Duration(minutes: 2);
    final dueByDistance = _lastEtaCalcPosition == null ||
        Geolocator.distanceBetween(
              _lastEtaCalcPosition!.lat,
              _lastEtaCalcPosition!.lng,
              myPoint.lat,
              myPoint.lng,
            ) >=
            300;

    if (!(dueByTime && dueByDistance)) return;

    _etaCalcInFlight = true;
    _lastEtaCalcAt = now;
    final myPosition = RouteStop(lat: myPoint.lat, lng: myPoint.lng);
    _lastEtaCalcPosition = myPosition;

    final remainingWaypoints = _remainingWaypoints(myPosition, _route!.waypoints);

    _directionsService
        .route(
          origin: myPosition,
          destination: _route!.destination,
          waypoints: remainingWaypoints,
        )
        .then((result) {
      if (!mounted) return;
      setState(() {
        _myEtaDistanceMeters = result.distanceMeters.toDouble();
        _myEtaDuration = Duration(seconds: result.durationSeconds);
        _myEtaRemainingStops = remainingWaypoints.length;
        _myRoutePolyline = result.polyline;
      });
    }).catchError((_) {
      // A live ETA is a nice-to-have - don't interrupt the user with an
      // error toast for a background recalculation failure.
    }).whenComplete(() => _etaCalcInFlight = false);
  }

  /// Waypoints this member hasn't reached yet, in order, starting from the
  /// first one still further than [_waypointArrivalRadiusMeters] away.
  /// Anything before that is treated as already passed. This is a simple
  /// proximity heuristic recomputed fresh from wherever the member
  /// currently is - not persisted "visited" state - so it self-corrects if
  /// someone backtracks, and needs no extra sync with other members.
  List<RouteStop> _remainingWaypoints(RouteStop myPosition, List<RouteStop> waypoints) {
    for (var i = 0; i < waypoints.length; i++) {
      final distanceToStop = Geolocator.distanceBetween(
        myPosition.lat,
        myPosition.lng,
        waypoints[i].lat,
        waypoints[i].lng,
      );
      if (distanceToStop > _waypointArrivalRadiusMeters) {
        return waypoints.sublist(i);
      }
    }
    return const [];
  }

  Set<Marker> _buildRouteMarkers(RoutePlan route) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('route_destination'),
        position: LatLng(route.destination.lat, route.destination.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
    };
    for (var i = 0; i < route.waypoints.length; i++) {
      final w = route.waypoints[i];
      markers.add(Marker(
        markerId: MarkerId('route_waypoint_$i'),
        position: LatLng(w.lat, w.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: 'Stop ${i + 1}'),
      ));
    }
    return markers;
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    _connectivitySub?.cancel();
    _groupStatusSub?.cancel();
    _locationService.stopSharing();
    super.dispose();
  }

  /// Compares this frame's statuses against the last known ones and
  /// pops a brief toast for any member who just went stale/lost or who
  /// just came back - not for every render.
  void _checkForStatusTransitions(List<LocationPoint> points) {
    for (final p in points) {
      if (p.userId == _authService.uid) continue; // don't notify about self
      final previous = _lastKnownStatus[p.userId];
      final current = p.status;

      if (previous != null && previous != current) {
        String? message;
        if (current == SignalStatus.lost && previous != SignalStatus.lost) {
          message = '${p.displayName} lost signal';
        } else if (current == SignalStatus.live && previous == SignalStatus.lost) {
          message = '${p.displayName} is back online';
        }
        if (message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message!), duration: const Duration(seconds: 3)),
            );
          });
        }
      }
      _lastKnownStatus[p.userId] = current;
    }
  }

  Future<void> _toggleSharing() async {
    if (_sharing) {
      await _locationService.stopSharing();
      setState(() => _sharing = false);
      return;
    }

    final status = await _locationService.checkPermissionStatus();
    final alreadyGranted = status == LocationPermission.always ||
        status == LocationPermission.whileInUse;

    if (!alreadyGranted) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => LocationPermissionScreen(groupName: widget.group.name),
          fullscreenDialog: true,
        ),
      );
      if (result != true) return; // user declined or permission not granted
    }

    try {
      await _locationService.startSharing(
        groupId: widget.group.id,
        userId: _authService.uid!,
        displayName: _authService.currentUser?.displayName ?? 'Me',
      );
      setState(() => _sharing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // Color identifies WHO a marker is (consistent per user, matched by the
  // roster's avatar dot - see ConvoyStatusList), separate from signal
  // status, which is now shown via opacity instead of color: markers used
  // to all look identical whenever multiple members were "live" (same
  // orange pin), making it impossible to tell who was who without tapping
  // each one.
  Set<Marker> _buildMarkers(List<LocationPoint> points) {
    return points.map((p) {
      final hue = markerHueForUser(p.userId);
      final alpha = switch (p.status) {
        SignalStatus.live => 1.0,
        SignalStatus.weak => 0.65,
        SignalStatus.lost => 0.35,
      };
      final snippet = switch (p.status) {
        SignalStatus.live => '${p.speed.toStringAsFixed(0)} m/s',
        SignalStatus.weak => 'Weak signal · ${p.lastSeenLabel}',
        SignalStatus.lost => 'Signal lost · last seen ${p.lastSeenLabel}',
      };
      return Marker(
        markerId: MarkerId(p.userId),
        position: LatLng(p.lat, p.lng),
        infoWindow: InfoWindow(title: p.displayName, snippet: snippet),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        alpha: alpha,
      );
    }).toSet();
  }

  /// Fits the camera to show every *actively tracked* member marker (members
  /// whose signal is `lost` are excluded so a phone that's been off for
  /// hours doesn't drag the zoom/pan out to include a stale pin - they still
  /// get a marker, just not counted for framing) plus, when a route is set,
  /// its destination and waypoints - so the manual refit and the initial
  /// auto-fit both reveal the whole planned trip, not just where people are.
  void _fitCameraToPoints(List<LocationPoint> points) {
    if (_mapController == null) return;

    final active = points.where((p) => p.status != SignalStatus.lost);
    final route = _route;
    final routeLats = route == null
        ? const <double>[]
        : [route.destination.lat, ...route.waypoints.map((w) => w.lat)];
    final routeLngs = route == null
        ? const <double>[]
        : [route.destination.lng, ...route.waypoints.map((w) => w.lng)];

    final lats = [...active.map((p) => p.lat), ...routeLats];
    final lngs = [...active.map((p) => p.lng), ...routeLngs];
    if (lats.isEmpty) return; // nothing to frame - leave camera as-is

    if (lats.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lats.first, lngs.first), 14),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(lats.reduce(min), lngs.reduce(min)),
      northeast: LatLng(lats.reduce(max), lngs.reduce(max)),
    );

    // Padding keeps markers from sitting flush against screen edges/UI
    // chrome (roster button, share button, offline banner).
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _maybeAutoFit(List<LocationPoint> points) {
    if (_hasAutoFitted || _mapController == null) return;
    final hasActive = points.any((p) => p.status != SignalStatus.lost);
    if (!hasActive && _route == null) return;
    _hasAutoFitted = true;
    // Let the map finish its first frame before animating the camera.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitCameraToPoints(points));
  }

  void _showStatusList(List<LocationPoint> points) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: ConvoyStatusList(
          points: points,
          currentUserId: _authService.uid ?? '',
          onSelect: (p) {
            Navigator.pop(context);
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(p.lat, p.lng), 15),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          if (_isOwner && !_groupEnded)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'extend') _extendTrip();
                if (value == 'end') _confirmEndTrip();
                if (value == 'route') _openSetRoute();
                if (value == 'clear_route') _clearRoute();
                if (value == 'toggle_invite') _toggleMembersCanInvite();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'extend',
                  child: ListTile(
                    leading: Icon(Icons.update),
                    title: Text('Extend trip 24h'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'end',
                  child: ListTile(
                    leading: Icon(Icons.stop_circle_outlined, color: Colors.red),
                    title: Text('End trip'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'route',
                  child: ListTile(
                    leading: const Icon(Icons.alt_route),
                    title: Text(_route == null ? 'Set route' : 'Edit route'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (_route != null)
                  const PopupMenuItem(
                    value: 'clear_route',
                    child: ListTile(
                      leading: Icon(Icons.route_outlined, color: Colors.red),
                      title: Text('Clear route'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'toggle_invite',
                  child: ListTile(
                    leading: Icon(
                      _membersCanInvite ? Icons.check_box : Icons.check_box_outline_blank,
                    ),
                    title: const Text('Allow members to invite'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          // Hidden from non-owners when the owner has turned off member
          // invites - the owner always keeps access to it.
          if (_isOwner || _membersCanInvite)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Invite others',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InviteScreen(group: widget.group)),
                );
              },
            ),
        ],
      ),
      body: StreamBuilder<List<LocationPoint>>(
        stream: _locationService.groupLocationsStream(widget.group.id),
        builder: (context, snapshot) {
          final points = snapshot.data ?? [];
          _checkForStatusTransitions(points);
          _maybeAutoFit(points);
          _maybeRecalculateMyEta(points);
          final route = _route;
          final markers = {
            ..._buildMarkers(points),
            if (route != null) ..._buildRouteMarkers(route),
          };
          final myRoutePolyline = _myRoutePolyline;
          final polylines = route == null
              ? const <Polyline>{}
              : {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: decodePolyline(route.polyline),
                    color: Colors.blueAccent,
                    width: 5,
                  ),
                  // This viewer's own remaining path to the destination, in
                  // their marker's color - overlaid on the shared plan above
                  // since that one is fixed to how the route looked from the
                  // owner's position when they set it, not where everyone
                  // else actually is now.
                  if (myRoutePolyline != null)
                    Polyline(
                      polylineId: const PolylineId('my_route'),
                      points: decodePolyline(myRoutePolyline),
                      color: colorForMarkerHue(
                        markerHueForUser(_authService.uid!),
                      ),
                      width: 5,
                      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                    ),
                };
          final lostCount =
              points.where((p) => p.status == SignalStatus.lost).length;
          final expiryBanner = _buildExpiryBanner();

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(0, 0),
                  zoom: 4,
                ),
                markers: markers,
                polylines: polylines,
                onMapCreated: (c) {
                  _mapController = c;
                  // Map may finish initializing after points already
                  // arrived (e.g. slow device) - fit immediately in that case.
                  _maybeAutoFit(points);
                },
                myLocationEnabled: true,
              ),

              // Top banners - offline warning and/or trip-expiry warning,
              // stacked so neither overlaps the other or the map controls.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    if (_deviceOffline)
                      Container(
                        width: double.infinity,
                        color: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: const Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "You're offline — your location isn't updating",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (expiryBanner != null) expiryBanner,
                  ],
                ),
              ),

              // Roster button - badges with a count if anyone's signal is lost
              Positioned(
                top: 12,
                right: 12,
                child: Badge(
                  label: Text('$lostCount'),
                  isLabelVisible: lostCount > 0,
                  backgroundColor: Colors.red,
                  child: FloatingActionButton.small(
                    heroTag: 'roster',
                    onPressed: () => _showStatusList(points),
                    child: const Icon(Icons.groups),
                  ),
                ),
              ),

              // Manual re-fit - lets users recenter on the whole group
              // after they've panned/zoomed away from the auto-fit view.
              Positioned(
                top: 12,
                right: 68,
                child: FloatingActionButton.small(
                  heroTag: 'refit',
                  onPressed: () => _fitCameraToPoints(points),
                  child: const Icon(Icons.center_focus_strong),
                ),
              ),

              // Route info - static full-trip distance/duration, plus this
              // viewer's own live progress once the first throttled
              // recalculation completes (see _maybeRecalculateMyEta).
              if (route != null)
                Positioned(
                  bottom: 90,
                  left: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RouteInfoChip(
                        icon: Icons.alt_route,
                        label: 'Full route: '
                            '${_formatDistanceDuration(route.distanceMeters, route.durationSeconds)}',
                      ),
                      if (_myEtaDuration != null && _myEtaDistanceMeters != null) ...[
                        const SizedBox(height: 6),
                        _RouteInfoChip(
                          icon: Icons.navigation,
                          label: 'You: '
                              '${_formatDistanceDuration(_myEtaDistanceMeters!.round(), _myEtaDuration!.inSeconds)}'
                              ' to destination'
                              '${_myEtaRemainingStops > 0 ? ' ($_myEtaRemainingStops stop${_myEtaRemainingStops == 1 ? '' : 's'} left)' : ''}',
                        ),
                      ],
                    ],
                  ),
                ),

              // Bottom-left, not bottom-right, so it doesn't sit under the
              // Google Maps zoom controls the SDK draws in that corner.
              Positioned(
                bottom: 24,
                left: 24,
                child: FloatingActionButton(
                  heroTag: 'toggleSharing',
                  onPressed: _toggleSharing,
                  backgroundColor: _sharing ? Colors.red : Colors.deepOrange,
                  tooltip: _sharing ? 'Stop sharing my location' : 'Start sharing my location',
                  child: Icon(_sharing ? Icons.location_off : Icons.location_on),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RouteInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
