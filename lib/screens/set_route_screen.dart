import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/group.dart';
import '../models/route_plan.dart';
import '../services/directions_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import 'location_permission_screen.dart';

enum _TapMode { destination, stop }

/// Owner-only screen for planning (or amending) the group's shared trip:
/// tap the map to place the destination, tap again in "Add stop" mode to
/// append ordered waypoints, drag to reorder them, then save. Saving looks
/// up the owner's current position as the route's origin and resolves the
/// whole thing into an actual driving route via [DirectionsService].
class SetRouteScreen extends StatefulWidget {
  final ConvoyGroup group;
  final RoutePlan? initialRoute;

  const SetRouteScreen({super.key, required this.group, this.initialRoute});

  @override
  State<SetRouteScreen> createState() => _SetRouteScreenState();
}

class _SetRouteScreenState extends State<SetRouteScreen> {
  final _locationService = LocationService();
  final _groupService = GroupService();
  final _directionsService = DirectionsService();

  // Roughly fits a 50mi radius around the center point on a phone screen -
  // keeps the initial view scoped to a plausible destination range instead
  // of opening on the whole world.
  static const _nearbyZoom = 9.0;
  static const _worldFallbackCamera = CameraPosition(target: LatLng(0, 0), zoom: 2);

  _TapMode _mode = _TapMode.destination;
  RouteStop? _destination;
  List<RouteStop> _waypoints = [];
  bool _saving = false;
  late final Future<CameraPosition> _initialCameraFuture;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRoute;
    if (initial != null) {
      _destination = initial.destination;
      _waypoints = List.of(initial.waypoints);
      _initialCameraFuture = Future.value(CameraPosition(
        target: LatLng(initial.destination.lat, initial.destination.lng),
        zoom: 12,
      ));
    } else {
      _initialCameraFuture = _resolveNearbyCamera();
    }
  }

  // Actively fetches a fresh position rather than relying on
  // Geolocator.getLastKnownPosition(), which is frequently unpopulated
  // (e.g. right after a fresh install/process start) and would silently
  // fall back to a world view - exactly the friction this replaces.
  // Doesn't force a permission prompt on screen-open: if permission isn't
  // already granted, this just falls back to the world view; the prompt
  // stays tied to the actual save action in _save() instead.
  Future<CameraPosition> _resolveNearbyCamera() async {
    try {
      final status = await _locationService.checkPermissionStatus();
      final granted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
      if (!granted) return _worldFallbackCamera;

      final position = await _locationService.getCurrentPosition();
      return CameraPosition(
        target: LatLng(position.latitude, position.longitude),
        zoom: _nearbyZoom,
      );
    } catch (_) {
      return _worldFallbackCamera;
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      if (_mode == _TapMode.destination) {
        _destination = RouteStop(lat: point.latitude, lng: point.longitude);
      } else {
        _waypoints = [..._waypoints, RouteStop(lat: point.latitude, lng: point.longitude)];
      }
    });
  }

  void _removeWaypoint(int index) {
    setState(() => _waypoints = [..._waypoints]..removeAt(index));
  }

  void _reorderWaypoints(int oldIndex, int newIndex) {
    setState(() {
      final updated = [..._waypoints];
      if (newIndex > oldIndex) newIndex -= 1;
      final item = updated.removeAt(oldIndex);
      updated.insert(newIndex, item);
      _waypoints = updated;
    });
  }

  Future<void> _save() async {
    if (_destination == null || _saving) return;
    setState(() => _saving = true);
    try {
      final status = await _locationService.checkPermissionStatus();
      final alreadyGranted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;

      if (!mounted) return;
      if (!alreadyGranted) {
        final granted = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LocationPermissionScreen(groupName: widget.group.name),
            fullscreenDialog: true,
          ),
        );
        if (granted != true) {
          setState(() => _saving = false);
          return;
        }
      }

      final position = await _locationService.getCurrentPosition();
      final origin = RouteStop(lat: position.latitude, lng: position.longitude);

      final route = await _directionsService.route(
        origin: origin,
        destination: _destination!,
        waypoints: _waypoints,
      );

      await _groupService.setRoute(widget.group.id, route);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    if (_destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(_destination!.lat, _destination!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    for (var i = 0; i < _waypoints.length; i++) {
      final w = _waypoints[i];
      markers.add(Marker(
        markerId: MarkerId('waypoint_$i'),
        position: LatLng(w.lat, w.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: 'Stop ${i + 1}'),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialRoute;

    return Scaffold(
      appBar: AppBar(
        title: Text(initial != null ? 'Edit route' : 'Set route'),
        actions: [
          TextButton(
            onPressed: _destination == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: FutureBuilder<CameraPosition>(
        future: _initialCameraFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final startCamera = snapshot.data!;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: startCamera,
                      onTap: _onMapTap,
                      markers: _buildMarkers(),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Destination'),
                            selected: _mode == _TapMode.destination,
                            onSelected: (_) => setState(() => _mode = _TapMode.destination),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Add stop'),
                            selected: _mode == _TapMode.stop,
                            onSelected: (_) => setState(() => _mode = _TapMode.stop),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.flag, color: Colors.deepPurple),
                        title: Text(_destination == null
                            ? 'Tap the map to set a destination'
                            : 'Destination set — tap the map to move it'),
                        dense: true,
                      ),
                      Flexible(
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          itemCount: _waypoints.length,
                          onReorder: _reorderWaypoints,
                          itemBuilder: (context, index) => ListTile(
                            key: ValueKey('waypoint_$index'),
                            leading: CircleAvatar(radius: 12, child: Text('${index + 1}')),
                            title: Text(
                              '${_waypoints[index].lat.toStringAsFixed(4)}, '
                              '${_waypoints[index].lng.toStringAsFixed(4)}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => _removeWaypoint(index),
                            ),
                          ),
                        ),
                      ),
                    ],
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
