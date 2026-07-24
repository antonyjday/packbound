import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/group.dart';
import '../models/place_suggestion.dart';
import '../models/route_plan.dart';
import '../models/trip_type.dart';
import '../services/directions_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../utils/map_styles.dart';
import 'location_permission_screen.dart';

enum _TapMode { origin, destination, stop }

/// Owner-only screen for planning (or amending) the group's shared trip:
/// tap the map to place the destination, tap again in "Add stop" mode to
/// append ordered waypoints, drag to reorder them, then save. The starting
/// point defaults to the owner's current position at save time, but can be
/// overridden by tapping the map in "Start" mode - useful for planning a
/// trip ahead of time from somewhere other than where the owner happens to
/// be right now. Saving resolves the whole thing into an actual driving
/// route via [DirectionsService].
class SetRouteScreen extends StatefulWidget {
  final ConvoyGroup group;
  final RoutePlan? initialRoute;

  // Passed explicitly rather than read from group.tripType - MapScreen keeps
  // a live-synced _tripType field (the menu's "Trip type" picker can change
  // it without rebuilding MapScreen's widget.group), so relying on
  // group.tripType here would silently use a stale mode if the owner
  // changed trip type and then opened this screen in the same session
  // (see the caller in MapScreen._openSetRoute).
  final TripType tripType;

  const SetRouteScreen({
    super.key,
    required this.group,
    required this.tripType,
    this.initialRoute,
  });

  @override
  State<SetRouteScreen> createState() => _SetRouteScreenState();
}

class _SetRouteScreenState extends State<SetRouteScreen> {
  final _locationService = LocationService();
  final _groupService = GroupService();
  final _directionsService = DirectionsService();
  final _placesService = PlacesService();

  // Fits a plausible destination range for the group's trip type on a phone
  // screen (see TripType.nearbyZoom) instead of a single fixed radius that's
  // right for driving but useless for a walk (too zoomed out) or a train
  // trip (too zoomed in).
  double get _nearbyZoom => widget.tripType.nearbyZoom;
  static const _worldFallbackCamera = CameraPosition(target: LatLng(0, 0), zoom: 2);

  _TapMode _mode = _TapMode.destination;
  RouteStop? _startingPoint;
  RouteStop? _destination;
  List<RouteStop> _waypoints = [];
  bool _saving = false;
  late final Future<CameraPosition> _initialCameraFuture;
  GoogleMapController? _mapController;
  RouteStop? _cameraBiasCenter; // roughly where the map's currently looking - see _resolveNearbyCamera

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  String? _searchSessionToken;
  List<PlaceSuggestion> _suggestions = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRoute;
    if (initial != null) {
      // Preserve the previously used starting point when editing, rather
      // than silently reverting to "defaults to current location" - the
      // owner may be amending the route from somewhere other than where
      // they originally set it.
      _startingPoint = initial.origin;
      _destination = initial.destination;
      _waypoints = List.of(initial.waypoints);
      _cameraBiasCenter = initial.destination;
      _initialCameraFuture = Future.value(CameraPosition(
        target: LatLng(initial.destination.lat, initial.destination.lng),
        zoom: 12,
      ));
    } else {
      _initialCameraFuture = _resolveNearbyCamera()
        ..then((camera) => _cameraBiasCenter =
            RouteStop(lat: camera.target.latitude, lng: camera.target.longitude));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    _setPointForCurrentMode(RouteStop(lat: point.latitude, lng: point.longitude));
  }

  /// Sets whichever point the current Start/Destination/Add-stop mode
  /// means right now - shared by both tapping the map and picking a
  /// search suggestion, so the two input methods behave identically.
  void _setPointForCurrentMode(RouteStop point) {
    setState(() {
      switch (_mode) {
        case _TapMode.origin:
          _startingPoint = point;
        case _TapMode.destination:
          _destination = point;
        case _TapMode.stop:
          _waypoints = [..._waypoints, point];
      }
    });
  }

  void _onSearchChanged(String input) {
    _searchDebounce?.cancel();
    // A 1-character prefix matches almost everything and is nearly always
    // followed by more typing before the user looks at results - skip the
    // billed autocomplete call until there's enough to narrow things down.
    if (input.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    // A fresh session token once a search starts from empty, reused for
    // every keystroke's autocomplete call and the eventual details lookup
    // - see PlacesService.newSessionToken.
    _searchSessionToken ??= _placesService.newSessionToken();

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final results = await _placesService.autocomplete(
          input,
          sessionToken: _searchSessionToken!,
          biasCenter: _cameraBiasCenter,
        );
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {
        // A failed autocomplete call is a nice-to-have miss, not worth an
        // error toast mid-typing - the user can just keep typing or fall
        // back to tapping the map.
        if (mounted) setState(() => _suggestions = []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    final sessionToken = _searchSessionToken;
    setState(() {
      _suggestions = [];
      _searchController.clear();
      _searchSessionToken = null; // done with this search session
    });
    _searchFocusNode.unfocus();

    try {
      final point = await _placesService.resolvePlace(
        suggestion.placeId,
        sessionToken: sessionToken ?? _placesService.newSessionToken(),
      );
      _setPointForCurrentMode(point);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(point.lat, point.lng), 15),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String _searchHintForMode() {
    switch (_mode) {
      case _TapMode.origin:
        return 'Search for a starting point';
      case _TapMode.destination:
        return 'Search for a destination';
      case _TapMode.stop:
        return 'Search for a stop';
    }
  }

  void _clearStartingPoint() => setState(() => _startingPoint = null);

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
      RouteStop origin;
      final manualStart = _startingPoint;
      if (manualStart != null) {
        // A manually-picked starting point needs no location permission at
        // all - it's just a map coordinate, same as the destination/stops.
        origin = manualStart;
      } else {
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
        origin = RouteStop(lat: position.latitude, lng: position.longitude);
      }

      final route = await _directionsService.route(
        origin: origin,
        destination: _destination!,
        waypoints: _waypoints,
        mode: widget.tripType.directionsMode,
      );

      await _groupService.setRoute(widget.group.id, route);
      if (mounted) {
        // Transit directions don't support waypoints at all (see
        // DirectionsService.route) - let the owner know their stops didn't
        // silently make it into the saved route, rather than them finding
        // out only once they notice the map doesn't show them.
        if (widget.tripType == TripType.train && _waypoints.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              "Train trips route point-to-point only - stops aren't supported "
              'and were not included in the saved route.',
            ),
            duration: Duration(seconds: 5),
          ));
        }
        Navigator.pop(context);
      }
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
    if (_startingPoint != null) {
      markers.add(Marker(
        markerId: const MarkerId('starting_point'),
        position: LatLng(_startingPoint!.lat, _startingPoint!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Starting point'),
      ));
    }
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
                      style: Theme.of(context).brightness == Brightness.dark
                          ? nightMapStyle
                          : null,
                      onTap: _onMapTap,
                      markers: _buildMarkers(),
                      onMapCreated: (c) => _mapController = c,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(28),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: _searchHintForMode(),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searching
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      )
                                    : (_searchController.text.isEmpty
                                        ? null
                                        : IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              _searchController.clear();
                                              _searchDebounce?.cancel();
                                              setState(() {
                                                _suggestions = [];
                                                _searchSessionToken = null;
                                              });
                                            },
                                          )),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          if (_suggestions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 260),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final s = _suggestions[index];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_on_outlined),
                                    title: Text(s.primaryText),
                                    subtitle: s.secondaryText == null
                                        ? null
                                        : Text(
                                            s.secondaryText!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () => _selectSuggestion(s),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Start'),
                                selected: _mode == _TapMode.origin,
                                onSelected: (_) => setState(() => _mode = _TapMode.origin),
                              ),
                              const SizedBox(width: 8),
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
                        leading: const Icon(Icons.trip_origin, color: Colors.green),
                        title: Text(_startingPoint == null
                            ? 'Starting point defaults to your location when saved'
                            : 'Starting point set — tap the map to move it'),
                        trailing: _startingPoint == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Reset to current location',
                                onPressed: _clearStartingPoint,
                              ),
                        dense: true,
                      ),
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
