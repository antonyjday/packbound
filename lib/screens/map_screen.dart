import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';
import '../models/location_point.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import 'location_permission_screen.dart';
import 'invite_screen.dart';
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
  bool _sharing = false;
  bool _isOwner = false;
  GoogleMapController? _mapController;

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

  // Banner is dismissible, but reappears if the severity level goes up
  // (e.g. dismissed the 4h-out warning, but the 1h-out one still shows).
  int _dismissedWarningLevel = 0;

  static const earlyWarningLead = Duration(hours: 4);
  static const finalWarningLead = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
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

  Set<Marker> _buildMarkers(List<LocationPoint> points) {
    return points.map((p) {
      final hue = switch (p.status) {
        SignalStatus.live => BitmapDescriptor.hueOrange,
        SignalStatus.weak => BitmapDescriptor.hueYellow,
        SignalStatus.lost => BitmapDescriptor.hueRed,
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
      );
    }).toSet();
  }

  /// Fits the camera to show every *actively tracked* marker - members
  /// whose signal is `lost` are excluded so a phone that's been off for
  /// hours doesn't drag the zoom/pan out to include a stale pin. Lost
  /// members still get a marker on the map, just not counted for framing.
  void _fitCameraToPoints(List<LocationPoint> points) {
    if (_mapController == null) return;

    final active = points.where((p) => p.status != SignalStatus.lost).toList();
    if (active.isEmpty) return; // nothing actively tracked - leave camera as-is

    if (active.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(active.first.lat, active.first.lng), 14),
      );
      return;
    }

    double minLat = active.first.lat, maxLat = active.first.lat;
    double minLng = active.first.lng, maxLng = active.first.lng;
    for (final p in active) {
      minLat = p.lat < minLat ? p.lat : minLat;
      maxLat = p.lat > maxLat ? p.lat : maxLat;
      minLng = p.lng < minLng ? p.lng : minLng;
      maxLng = p.lng > maxLng ? p.lng : maxLng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Padding keeps markers from sitting flush against screen edges/UI
    // chrome (roster button, share button, offline banner).
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _maybeAutoFit(List<LocationPoint> points) {
    if (_hasAutoFitted || _mapController == null) return;
    final hasActive = points.any((p) => p.status != SignalStatus.lost);
    if (!hasActive) return;
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
              ],
            ),
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
          final markers = _buildMarkers(points);
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

              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: FilledButton.icon(
                  onPressed: _toggleSharing,
                  icon: Icon(_sharing ? Icons.location_off : Icons.location_on),
                  label: Text(_sharing ? 'Stop sharing my location' : 'Start sharing my location'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _sharing ? Colors.red : Colors.deepOrange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
