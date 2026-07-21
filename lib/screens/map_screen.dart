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
import '../utils/navigation_progress.dart';
import '../utils/polyline_codec.dart';
import '../utils/route_progress.dart';
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

  // True while an animateCamera call *we* triggered is still in flight -
  // lets the GoogleMap's onCameraMoveStarted callback tell our own
  // programmatic moves (auto-fit, follow-mode, step-through, ...) apart
  // from the user actually dragging/pinching the map themselves, since
  // both fire the same callback. Set right before every animateCamera call
  // (see _animateCamera) and cleared again in onCameraIdle.
  bool _programmaticCameraMove = false;

  // While set (and not yet in the past), follow-mode below won't move the
  // camera - sees the user picked a specific view (dragged the map,
  // opened the roster and jumped to someone, stepped through the trip)
  // and gives it 30s before snapping back to auto-following this device's
  // own position. See _registerManualCameraOverride/_maybeFollowMe.
  DateTime? _cameraOverrideUntil;

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

  // This viewer's own turn-by-turn instructions to the destination, from
  // the same throttled Directions call as the ETA/route line above - see
  // _maybeRecalculateMyEta. Which one is "next" is recomputed live on every
  // location tick (cheap local geometry, no extra API calls) rather than
  // waiting for the next throttled recalculation - see nextNavigationStep.
  List<RouteStep> _myRouteSteps = [];
  bool _etaCalcInFlight = false;
  DateTime? _lastEtaCalcAt;
  RouteStop? _lastEtaCalcPosition;

  // Which leg of the route the "step through trip" button last jumped the
  // camera to: -1 means "at the start point", 0..waypoints.length-1 are the
  // stops in order, waypoints.length is the destination, and
  // waypoints.length + 1 is this device's own current location. Pressing
  // again advances one leg, wrapping back to -1 after that final "my
  // location" step. Reset to -1 whenever the route itself changes (see the
  // group-doc listener).
  int _routeStepIndex = -1;

  // How many of this member's leading legs (start point, then waypoints in
  // order) the "skip ahead" button has manually forced to count as passed,
  // regardless of actual proximity - see _remainingLegs/_toggleSkipRouteLeg.
  // Reset to 0 whenever the route itself changes.
  int _manualRouteSkipCount = 0;

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

  // Detects this device's own membership doc being deleted - i.e. the
  // owner removed this member (see GroupService.removeMember) - distinct
  // from the group ending, which is handled above via the group doc's
  // status field instead. Guards against firing more than once.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _membershipSub;
  bool _removedFromGroup = false;

  // Set once the first membership snapshot has been processed - lets
  // _handleMembershipSnapshot tell "became owner just now" (worth a
  // notification) apart from "was already owner when this screen opened"
  // (not a change, nothing to announce).
  bool _hasSeenMembership = false;

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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
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
        .listen(
          (doc) async {
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
                _myRouteSteps = [];
                _lastEtaCalcAt = null;
                _lastEtaCalcPosition = null;
                _routeStepIndex = -1;
                _manualRouteSkipCount = 0;
              });
              // A route created/changed *after* this device already got its
              // initial view (_hasAutoFitted) puts the camera on its start point
              // specifically - a deliberate "here's where the new plan starts"
              // cue, since the owner may be planning a trip that starts somewhere
              // other than where members currently are. But on first ever join,
              // _maybeAutoFit's fit-everything view (start point, waypoints,
              // destination, and this device's own location all at once) is what
              // should be shown instead - overriding it here would fight with
              // that, or short-circuit it entirely if the route arrives first.
              if (newRoute != null && _hasAutoFitted) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _focusOnRouteStart(newRoute),
                );
              }
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
                    content: Text(
                      'This trip has ended. Location sharing has stopped.',
                    ),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            }
          },
          onError: (_) {
            // Once this device is no longer a member (left, or was removed),
            // this listener's own read permission goes with it - an expected
            // terminal state, not something to surface as an unhandled
            // exception. dispose() (leave/removal both navigate away) cancels
            // the subscription shortly after anyway.
          },
        );

    _membershipSub = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.group.id)
        .collection('members')
        .doc(_authService.uid)
        .snapshots()
        .listen(
          (doc) => _handleMembershipSnapshot(doc),
          // NOT just quiet log-noise suppression: reading your OWN
          // membership doc requires isMember(groupId), which itself
          // depends on that exact doc's existence - so the moment it's
          // deleted (owner removed you, or you left), your read access
          // to observe that fact disappears too. Firestore reports that
          // as a permission-denied *error* on this listener, not a
          // graceful "document doesn't exist" data event, so this is
          // actually the primary signal _handleMembershipRemoved needs -
          // doc.exists==false in _handleMembershipSnapshot mostly only
          // ever fires from the stale-cache case handled there instead.
          onError: (_) => _handleMembershipRemoved(),
        );

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn\'t extend trip: $e')));
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
          Icon(
            urgent ? Icons.warning_amber : Icons.access_time,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _isOwner
                  ? 'Trip ends in $label. Extend it now if the convoy isn\'t done yet.'
                  : 'Trip ends in $label. Ask the owner to extend if you\'re not done.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_isOwner)
            TextButton(
              onPressed: _extendTrip,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: urgent
                    ? Colors.red.shade700
                    : Colors.orange.shade800,
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

  /// Turn-by-turn instruction bar - the current maneuver plus a live
  /// countdown to it, satnav-style. [distanceMeters] is this device's
  /// current distance to the step's endpoint, recomputed fresh on every
  /// rebuild (see the StreamBuilder above), not throttled like the step
  /// list itself. [text]/[icon] are already resolved by the caller (see
  /// classifyTurnManeuver/relabelHeadInstruction/maneuverIcon in
  /// navigation_progress.dart) since which one applies depends on this
  /// device's live heading, not just the step itself.
  Widget _buildNavigationBar(String text, IconData icon, double distanceMeters) {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade900,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatStepDistance(distanceMeters),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Feet close-up (rounded to the nearest 50ft, like real satnav apps),
  // miles once far enough out that sub-mile precision isn't useful.
  String _formatStepDistance(double meters) {
    final feet = meters * 3.28084;
    if (feet < 1000) {
      final roundedFeet = (feet / 50).round() * 50;
      return 'In $roundedFeet ft';
    }
    final miles = meters / 1609.34;
    return 'In ${miles.toStringAsFixed(1)} mi';
  }

  /// Reacts to this device's own membership doc, live: keeps `_isOwner` in
  /// sync (not just set once at open - the owner role can change out from
  /// under this device, e.g. inheriting ownership when the previous owner
  /// leaves - see GroupService.leaveGroup) and detects the doc disappearing
  /// entirely, meaning the owner removed this member (see
  /// GroupService.removeMember). On removal, stops sharing right away
  /// (rather than letting the next location write silently fail with
  /// permission-denied), then tells the member and sends them back to the
  /// home screen once acknowledged.
  ///
  /// A voluntary leave (see _leaveTrip) deletes this same doc, so it marks
  /// `_removedFromGroup` itself beforehand to suppress the "you were
  /// removed" dialog for that self-initiated case.
  Future<void> _handleMembershipSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (doc.exists) {
      final isOwner = doc.data()?['role'] == 'owner';
      // Compare against the *old* _isOwner before it's overwritten below -
      // only a real transition (not just the initial value on first open)
      // is worth announcing.
      final justBecameOwner = _hasSeenMembership && !_isOwner && isOwner;
      _hasSeenMembership = true;

      if (isOwner != _isOwner && mounted) {
        setState(() => _isOwner = isOwner);
      }
      if (justBecameOwner && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "You're now the owner of this trip — the previous owner left.",
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    // A membership doc genuinely disappearing (owner removed this member,
    // or this member left) is only meaningful once membership has already
    // been confirmed to exist at least once. The very first snapshot
    // right after rejoining a group this device previously left/was
    // removed from can momentarily read a stale "not found" straight from
    // Firestore's local cache - a tombstone left over from the old,
    // deleted membership doc - before the fresh "exists" snapshot for the
    // new membership arrives. Treating that as a real removal would
    // incorrectly boot someone the moment they rejoin.
    if (!_hasSeenMembership) return;
    await _handleMembershipRemoved();
  }

  /// Tells this member they've been removed (or have left) and sends them
  /// back to the home screen once acknowledged. Called from two places:
  /// _handleMembershipSnapshot's doc.exists==false branch (the stale-cache
  /// case, gated on _hasSeenMembership there), and - the primary real-world
  /// path - _membershipSub's onError, since reading your OWN membership
  /// doc requires isMember(groupId), which itself depends on that exact
  /// doc's existence, so Firestore reports the moment it's deleted as a
  /// permission-denied *error* on this listener, not a graceful "document
  /// doesn't exist" data event.
  Future<void> _handleMembershipRemoved() async {
    if (_removedFromGroup || !mounted) return;
    _removedFromGroup = true;

    await _locationService.stopSharing();
    if (!mounted) return;
    setState(() => _sharing = false);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Removed from convoy'),
        content: const Text(
          "The owner has removed you from this convoy. You'll need a new "
          'invite to rejoin.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
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

  /// Any member can leave, including the owner. An owner leaving while
  /// other members are still around gets an extra warning-then-"are you
  /// sure" pair of dialogs instead of the single confirmation everyone
  /// else gets, since it has a bigger consequence (an automatic ownership
  /// handoff - see GroupService.leaveGroup) that's worth pausing on twice.
  Future<void> _confirmLeaveTrip() async {
    var ownerWithOthersPresent = false;
    if (_isOwner) {
      final members = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .collection('members')
          .get();
      ownerWithOthersPresent = members.docs.length > 1;
    }

    if (!mounted) return;

    if (ownerWithOthersPresent) {
      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("You're the owner"),
          content: const Text(
            "Other members are still in this trip. If you leave, ownership "
            "will automatically pass to whoever's been in the trip the "
            'longest.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (acknowledged != true || !mounted) return;

      final reallySure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text(
            "This will hand off ownership and remove you from the trip. "
            "This can't be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes, leave trip'),
            ),
          ],
        ),
      );
      if (reallySure != true) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave this trip?'),
          content: const Text(
            "You'll stop sharing and seeing this group's location. You can "
            'rejoin later with a new invite if needed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _leaveTrip();
  }

  Future<void> _leaveTrip() async {
    // Marked *before* the membership doc is actually deleted, so
    // _handleMembershipSnapshot's listener - which reacts to that same
    // deletion for the "the owner removed me" case - doesn't also pop up
    // its "you were removed" dialog for this self-initiated leave.
    _removedFromGroup = true;
    await _locationService.stopSharing();
    try {
      await _groupService.leaveGroup(widget.group.id, _authService.uid!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _openSetRoute() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SetRouteScreen(group: widget.group, initialRoute: _route),
      ),
    );
  }

  Future<void> _clearRoute() async {
    try {
      await _groupService.clearRoute(widget.group.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
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
  /// destination if due - throttled, both at most once every 2 minutes AND
  /// only once the device has moved 300m+ since the last calc, since an
  /// unthrottled per-location-tick (every ~3s) recalculation would multiply
  /// Directions API billing for no real benefit. Scoped to my own progress
  /// only, not a live ETA for every member shown to everyone, which would
  /// multiply calls by member count.
  void _maybeRecalculateMyEta(List<LocationPoint> points) {
    if (_route == null || _etaCalcInFlight) return;

    final mine = points.where((p) => p.userId == _authService.uid);
    if (mine.isEmpty) return;
    final myPoint = mine.first;

    final now = DateTime.now();
    final dueByTime =
        _lastEtaCalcAt == null ||
        now.difference(_lastEtaCalcAt!) >= const Duration(minutes: 2);
    final dueByDistance =
        _lastEtaCalcPosition == null ||
        Geolocator.distanceBetween(
              _lastEtaCalcPosition!.lat,
              _lastEtaCalcPosition!.lng,
              myPoint.lat,
              myPoint.lng,
            ) >=
            300;

    if (!(dueByTime && dueByDistance)) return;
    _recalculateMyEta(RouteStop(lat: myPoint.lat, lng: myPoint.lng));
  }

  /// Does the actual recalculation, bypassing the throttle above - used by
  /// [_maybeRecalculateMyEta] once it decides a recalc is due, and directly
  /// by the "skip ahead" button so toggling it is reflected immediately
  /// rather than waiting for the next throttled tick.
  void _recalculateMyEta(RouteStop myPosition) {
    if (_route == null || _etaCalcInFlight) return;

    _etaCalcInFlight = true;
    _lastEtaCalcAt = DateTime.now();
    _lastEtaCalcPosition = myPosition;

    // The trip's start point counts as this member's first leg too, same as
    // any other waypoint - a member who hasn't reached it yet should be
    // routed there before the rest of the planned stops/destination, not
    // straight past it to whatever's next on the plan (unless manually
    // skipped ahead - see remainingLegs in utils/route_progress.dart).
    final legsToGo = remainingLegs(
      myPosition,
      _route!,
      manualSkipCount: _manualRouteSkipCount,
    );

    _directionsService
        .route(
          origin: myPosition,
          destination: _route!.destination,
          waypoints: legsToGo,
        )
        .then((result) {
          if (!mounted) return;
          setState(() {
            _myEtaDistanceMeters = result.distanceMeters.toDouble();
            _myEtaDuration = Duration(seconds: result.durationSeconds);
            _myEtaRemainingStops = legsToGo.length;
            _myRoutePolyline = result.polyline;
            _myRouteSteps = result.steps;
          });
        })
        .catchError((_) {
          // A live ETA is a nice-to-have - don't interrupt the user with an
          // error toast for a background recalculation failure.
        })
        .whenComplete(() => _etaCalcInFlight = false);
  }

  /// Advances the manual "skip ahead" override by one leg (start point,
  /// then each waypoint in order); once every leg is skipped - meaning
  /// this member's route already goes straight to the destination -
  /// pressing again resets it, restoring the start point and all waypoints
  /// to their route. Forces an immediate recalculation rather than waiting
  /// for the next throttled tick, since a manual toggle like this should
  /// be reflected right away.
  void _toggleSkipRouteLeg(RoutePlan route, List<LocationPoint> points) {
    final legCount = 1 + route.waypoints.length; // start point + waypoints
    setState(() {
      _manualRouteSkipCount = _manualRouteSkipCount >= legCount
          ? 0
          : _manualRouteSkipCount + 1;
    });
    final mine = points.where((p) => p.userId == _authService.uid);
    if (mine.isNotEmpty) {
      _recalculateMyEta(RouteStop(lat: mine.first.lat, lng: mine.first.lng));
    }
  }

  /// Describes what the *next* press of the skip button will do.
  String _skipRouteLegLabel(RoutePlan route) {
    final legCount = 1 + route.waypoints.length;
    if (_manualRouteSkipCount >= legCount) return 'Resume full route';
    return _manualRouteSkipCount == 0
        ? 'Skip start point'
        : 'Skip stop $_manualRouteSkipCount';
  }

  Set<Marker> _buildRouteMarkers(RoutePlan route) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('route_start'),
        position: LatLng(route.origin.lat, route.origin.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Starting point'),
      ),
      Marker(
        markerId: const MarkerId('route_destination'),
        position: LatLng(route.destination.lat, route.destination.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
    };
    for (var i = 0; i < route.waypoints.length; i++) {
      final w = route.waypoints[i];
      markers.add(
        Marker(
          markerId: MarkerId('route_waypoint_$i'),
          position: LatLng(w.lat, w.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: 'Stop ${i + 1}'),
        ),
      );
    }
    return markers;
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    _connectivitySub?.cancel();
    _groupStatusSub?.cancel();
    _membershipSub?.cancel();
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
        } else if (current == SignalStatus.live &&
            previous == SignalStatus.lost) {
          message = '${p.displayName} is back online';
        }
        if (message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message!),
                duration: const Duration(seconds: 3),
              ),
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
    final alreadyGranted =
        status == LocationPermission.always ||
        status == LocationPermission.whileInUse;

    if (!alreadyGranted) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LocationPermissionScreen(groupName: widget.group.name),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // Color identifies WHO a marker is (consistent per user, matched by the
  // roster's avatar dot - see ConvoyStatusList), separate from signal
  // status, which is now shown via opacity instead of color: markers used
  // to all look identical whenever multiple members were "live" (same
  // orange pin), making it impossible to tell who was who without tapping
  // each one.
  Set<Marker> _buildMarkers(List<LocationPoint> points, Map<String, double> hues) {
    return points.map((p) {
      final hue = hues[p.userId]!;
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

  /// Every camera move this screen makes on its own (as opposed to the user
  /// dragging/pinching the map themselves) should go through here rather
  /// than calling `_mapController.animateCamera` directly - it flags the
  /// move as programmatic first so the GoogleMap's onCameraMoveStarted
  /// callback below doesn't mistake it for a manual interaction and (for
  /// no reason) pause follow-mode - see _maybeFollowMe.
  void _animateCamera(CameraUpdate update) {
    _programmaticCameraMove = true;
    _mapController?.animateCamera(update);
  }

  /// Pauses follow-mode for 30s - called wherever the user deliberately
  /// picks a different view than "wherever I am right now": dragging the
  /// map (see onCameraMoveStarted below), opening the roster and jumping
  /// to someone else, or stepping through the trip's stops. Follow-mode
  /// resumes on its own once the 30s elapses, as long as this device is
  /// still moving - see _maybeFollowMe.
  void _registerManualCameraOverride() {
    _cameraOverrideUntil = DateTime.now().add(const Duration(seconds: 30));
  }

  /// Re-centers the camera on this device's own position while it's
  /// actually moving (satnav-style "follow me"), unless a manual camera
  /// override is still in its 30s window - see _registerManualCameraOverride.
  /// Only kicks in after the initial join view has already happened
  /// (_hasAutoFitted), same gating as the rest of this screen's camera
  /// logic, and only moves the camera's *position*, not its zoom, so it
  /// doesn't fight whatever zoom level the user has chosen.
  void _maybeFollowMe(List<LocationPoint> points) {
    if (_mapController == null || !_hasAutoFitted) return;

    final overrideUntil = _cameraOverrideUntil;
    if (overrideUntil != null) {
      if (DateTime.now().isBefore(overrideUntil)) return;
      _cameraOverrideUntil = null; // 30s elapsed - resume following
    }

    final mine = points.where((p) => p.userId == _authService.uid);
    if (mine.isEmpty) return;
    final me = mine.first;
    if (me.speed < movingSpeedThresholdMps) return; // not moving - stay put

    _animateCamera(CameraUpdate.newLatLng(LatLng(me.lat, me.lng)));
  }

  /// Fits the camera to show every *actively tracked* member marker (members
  /// whose signal is `lost` are excluded so a phone that's been off for
  /// hours doesn't drag the zoom/pan out to include a stale pin - they still
  /// get a marker, just not counted for framing) plus, when a route is set,
  /// its start point, destination, and waypoints - so the manual refit and
  /// the initial auto-fit both reveal the whole planned trip relative to
  /// this device's own position, not just one or the other.
  void _fitCameraToPoints(List<LocationPoint> points) {
    if (_mapController == null) return;

    final active = points.where((p) => p.status != SignalStatus.lost);
    final route = _route;
    final routeLats = route == null
        ? const <double>[]
        : [
            route.origin.lat,
            route.destination.lat,
            ...route.waypoints.map((w) => w.lat),
          ];
    final routeLngs = route == null
        ? const <double>[]
        : [
            route.origin.lng,
            route.destination.lng,
            ...route.waypoints.map((w) => w.lng),
          ];

    final lats = [...active.map((p) => p.lat), ...routeLats];
    final lngs = [...active.map((p) => p.lng), ...routeLngs];
    if (lats.isEmpty) return; // nothing to frame - leave camera as-is

    if (lats.length == 1) {
      _animateCamera(
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
    _animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _maybeAutoFit(List<LocationPoint> points) {
    if (_hasAutoFitted || _mapController == null) return;
    final hasActive = points.any((p) => p.status != SignalStatus.lost);
    // A route alone (before this device's own location has arrived) is
    // still worth an initial fit, so someone joining a group that already
    // has a route set sees the whole planned trip immediately rather than
    // waiting on their own first location update.
    if (!hasActive && _route == null) return;
    _hasAutoFitted = true;
    // Let the map finish its first frame before animating the camera.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fitCameraToPoints(points),
    );
  }

  /// Centers the camera on the route's start point - used by the group-doc
  /// listener when a route is created/changed after this device's initial
  /// join view has already happened (see _hasAutoFitted there). Not used
  /// for the initial view itself; that's _fitCameraToPoints instead.
  /// Also gets follow-mode's 30s grace period (_registerManualCameraOverride)
  /// even though nobody clicked anything - otherwise, if this device happens
  /// to already be moving, follow-mode could re-center back onto it again
  /// within a few seconds and undo this "look, the route changed" cue
  /// almost as soon as it appears.
  void _focusOnRouteStart(RoutePlan route) {
    _registerManualCameraOverride();
    _animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(route.origin.lat, route.origin.lng),
        15,
      ),
    );
  }

  /// Every stop after the start, in order, ending with the destination -
  /// what the "step through trip" button cycles across.
  List<RouteStop> _routeLegsAfterStart(RoutePlan route) => [
    ...route.waypoints,
    route.destination,
  ];

  /// Advances the "step through trip" button one leg: first press lands on
  /// the first stop (or the destination directly, if there are no stops),
  /// each subsequent press moves to the next one, pressing again after the
  /// destination jumps to this device's own current location (if it has
  /// one - see [_myLocation]), and pressing once more wraps back around to
  /// the start point.
  void _stepThroughRoute(RoutePlan route, List<LocationPoint> points) {
    final legs = _routeLegsAfterStart(route);
    final myLocationIndex = legs.length; // one past the destination
    final nextIndex = _routeStepIndex + 1;
    setState(
      () => _routeStepIndex = nextIndex > myLocationIndex ? -1 : nextIndex,
    );

    final RouteStop? target;
    if (_routeStepIndex == -1) {
      target = route.origin;
    } else if (_routeStepIndex < legs.length) {
      target = legs[_routeStepIndex];
    } else {
      target = _myLocation(points);
    }
    if (target == null) return; // "my location" step, but no location yet
    _registerManualCameraOverride();
    _animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(target.lat, target.lng), 15),
    );
  }

  /// This device's own current position from the live locations stream, if
  /// it's sharing one yet - used by the "step through trip" button's final
  /// "my location" leg.
  RouteStop? _myLocation(List<LocationPoint> points) {
    final mine = points.where((p) => p.userId == _authService.uid);
    if (mine.isEmpty) return null;
    return RouteStop(lat: mine.first.lat, lng: mine.first.lng);
  }

  /// Describes what the *next* press of the step button will do, so the
  /// tooltip reflects the upcoming jump rather than the current position.
  String _nextRouteStepLabel(RoutePlan route) {
    final legs = _routeLegsAfterStart(route);
    final myLocationIndex = legs.length;
    final nextIndex = _routeStepIndex + 1;
    if (nextIndex > myLocationIndex) return 'Back to start';
    if (nextIndex == myLocationIndex) return 'Jump to your location';
    return nextIndex == legs.length - 1
        ? 'Jump to destination'
        : 'Jump to stop ${nextIndex + 1}';
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
          isOwner: _isOwner,
          onSelect: (p) {
            Navigator.pop(context);
            _registerManualCameraOverride();
            _animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(p.lat, p.lng), 15),
            );
          },
          onRemove: (p) => _confirmRemoveMember(context, p),
        ),
      ),
    );
  }

  /// Owner-only: confirms, then removes a member from the convoy entirely
  /// (see GroupService.removeMember) - [sheetContext] is the roster bottom
  /// sheet's own context, used both to anchor the confirmation dialog and
  /// to close the sheet afterward, same pattern as onSelect above.
  Future<void> _confirmRemoveMember(
    BuildContext sheetContext,
    LocationPoint point,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from convoy?'),
        content: Text(
          '${point.displayName} will be removed from the group and can no '
          "longer share or see the group's location. They can rejoin with a "
          'new invite if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _groupService.removeMember(widget.group.id, point.userId);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Shorter than the default 56, and with tightened action buttons
        // below, to leave more vertical room for the map.
        toolbarHeight: 40,
        titleSpacing: 12,
        title: Text(widget.group.name, style: const TextStyle(fontSize: 16)),
        actionsIconTheme: const IconThemeData(size: 20),
        actions: [
          // Persistent ambient indicator, not a one-off alert - stays up
          // the whole time you're owner (including right after inheriting
          // it - see the snackbar in _handleMembershipSnapshot for that
          // one-time transition notice) so it's never unclear whose trip
          // settings/route changes will actually apply. Lives in the app
          // bar (rather than its own banner) to keep more vertical room
          // for the map.
          if (_isOwner)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.deepPurple, size: 16),
                  SizedBox(width: 2),
                  Text(
                    'Owner',
                    style: TextStyle(
                      color: Colors.deepPurple,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // Always shown (not just for the owner) so every member has a
          // way to leave the trip - owner-only actions are added inside
          // conditionally instead of gating the whole menu.
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            onSelected: (value) {
              if (value == 'extend') _extendTrip();
              if (value == 'end') _confirmEndTrip();
              if (value == 'route') _openSetRoute();
              if (value == 'clear_route') _clearRoute();
              if (value == 'toggle_invite') _toggleMembersCanInvite();
              if (value == 'leave') _confirmLeaveTrip();
            },
            itemBuilder: (context) => [
              if (_isOwner && !_groupEnded) ...[
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
                    leading: Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.red,
                    ),
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
                      _membersCanInvite
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    title: const Text('Allow members to invite'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: 'leave',
                child: ListTile(
                  leading: Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text('Leave trip'),
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
              tooltip: 'Invite others',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InviteScreen(group: widget.group),
                  ),
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
          _maybeFollowMe(points);
          _maybeRecalculateMyEta(points);
          final route = _route;
          // Includes this device's own uid even if it isn't in `points` yet
          // (e.g. not sharing to Firestore, but still has a live GPS fix for
          // the "my route" polyline below) - otherwise that lookup would
          // have no entry for "me" at all.
          final memberHues = markerHuesForUsers(
            {...points.map((p) => p.userId), _authService.uid!},
          );
          final markers = {
            ..._buildMarkers(points, memberHues),
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
                      color: colorForMarkerHue(memberHues[_authService.uid!]!),
                      width: 5,
                      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                    ),
                };
          final lostCount = points
              .where((p) => p.status == SignalStatus.lost)
              .length;
          final expiryBanner = _buildExpiryBanner();

          // Next turn-by-turn instruction, if any - recomputed fresh from
          // wherever this device currently is on every rebuild (cheap local
          // geometry against the steps already fetched by the last
          // throttled recalculation), so the "in Xm" countdown keeps
          // updating between recalculations rather than only refreshing
          // every 2 minutes/300m like the steps themselves do.
          String? navInstructionText;
          IconData? navInstructionIcon;
          double? navDistanceMeters;
          final mine = points.where((p) => p.userId == _authService.uid);
          if (_myRouteSteps.isNotEmpty && mine.isNotEmpty) {
            final myLocation = mine.first;
            final myPos = RouteStop(lat: myLocation.lat, lng: myLocation.lng);
            final nextStep = nextNavigationStep(myPos, _myRouteSteps);
            if (nextStep != null) {
              navDistanceMeters = Geolocator.distanceBetween(
                myPos.lat,
                myPos.lng,
                nextStep.endLocation.lat,
                nextStep.endLocation.lng,
              );

              // The API only omits `maneuver` for its "Head <compass
              // direction> on/toward X" steps - relabel those relative to
              // this device's own heading instead (see
              // classifyTurnManeuver), but only while actually moving fast
              // enough for that heading to be trustworthy; otherwise fall
              // back to the API's own (still perfectly fine) wording.
              if (nextStep.maneuver == null &&
                  myLocation.speed >= movingSpeedThresholdMps) {
                final stepBearing = Geolocator.bearingBetween(
                  nextStep.startLocation.lat,
                  nextStep.startLocation.lng,
                  nextStep.endLocation.lat,
                  nextStep.endLocation.lng,
                );
                final syntheticManeuver = classifyTurnManeuver(
                  myLocation.heading,
                  stepBearing,
                );
                navInstructionText =
                    relabelHeadInstruction(nextStep.instruction, syntheticManeuver);
                navInstructionIcon = maneuverIcon(syntheticManeuver);
              } else {
                navInstructionText = nextStep.instruction;
                navInstructionIcon = maneuverIcon(nextStep.maneuver);
              }
            }
          }

          return Column(
            children: [
              // Turn-by-turn instruction bar - above the offline/trip-expiry
              // banners below, since it's the most immediately actionable
              // info while actually driving, same placement satnav apps use.
              if (navInstructionText != null)
                _buildNavigationBar(
                  navInstructionText,
                  navInstructionIcon!,
                  navDistanceMeters!,
                ),

              // Top banners - offline warning and/or trip-expiry warning,
              // stacked so neither overlaps the other. In normal in-flow
              // layout (not overlaid on the map via Positioned) so they push
              // the map and its corner buttons down when present - a fixed
              // height/text can wrap to 2 lines depending on device width
              // and owner-vs-member copy length, and overlaying at a fixed
              // top offset previously let that wrapped text run under the
              // corner buttons.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_deviceOffline)
                    Container(
                      width: double.infinity,
                      color: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
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
              Expanded(
                child: Stack(
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
                        // Map may finish initializing after points/route already
                        // arrived (e.g. slow device) - fit immediately in that case.
                        _maybeAutoFit(points);
                      },
                      // Distinguishes the user dragging/pinching the map
                      // themselves from a move *we* triggered (both fire
                      // onCameraMoveStarted) - see _animateCamera. A real
                      // manual drag pauses follow-mode for 30s, same as
                      // picking a roster member or stepping through the trip.
                      onCameraMoveStarted: () {
                        if (!_programmaticCameraMove) {
                          _registerManualCameraOverride();
                        }
                      },
                      onCameraIdle: () => _programmaticCameraMove = false,
                      myLocationEnabled: true,
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
                        onPressed: () {
                          _registerManualCameraOverride();
                          _fitCameraToPoints(points);
                        },
                        child: const Icon(Icons.center_focus_strong),
                      ),
                    ),

                    // Steps the camera through the trip: start point, then each
                    // stop in order, then the destination, then this device's own
                    // current location, then wraps back to the start - see
                    // _stepThroughRoute.
                    if (route != null)
                      Positioned(
                        top: 12,
                        right: 124,
                        child: FloatingActionButton.small(
                          heroTag: 'stepRoute',
                          onPressed: () => _stepThroughRoute(route, points),
                          tooltip: _nextRouteStepLabel(route),
                          child: const Icon(Icons.skip_next),
                        ),
                      ),

                    // Manually skips this member's own live route/ETA past legs
                    // it would otherwise still be routed to (starting with the
                    // start point, then each waypoint) - e.g. "I'm not going to
                    // the meetup point, just route me onward". Once every leg is
                    // skipped (routing straight to the destination), pressing
                    // again restores the full planned route - see
                    // _toggleSkipRouteLeg. Unlike the step button above, this
                    // changes the actual route/ETA, not just the camera.
                    if (route != null)
                      Positioned(
                        top: 12,
                        right: 180,
                        child: FloatingActionButton.small(
                          heroTag: 'skipRouteLeg',
                          onPressed: () => _toggleSkipRouteLeg(route, points),
                          tooltip: _skipRouteLegLabel(route),
                          child: Icon(
                            _manualRouteSkipCount >= 1 + route.waypoints.length
                                ? Icons.restore
                                : Icons.fast_forward,
                          ),
                        ),
                      ),

                    // Route info - a legend for the start/stop/destination marker
                    // colors (otherwise only distinguishable by tapping each one),
                    // the static full-trip distance/duration, plus this viewer's
                    // own live progress once the first throttled recalculation
                    // completes (see _maybeRecalculateMyEta). Anchored to the
                    // right of the location-sharing button (56px wide, at
                    // left: 24) rather than spanning the bottom of the map, to
                    // leave more of the map itself visible. Stacked top-to-bottom
                    // in portrait, but laid out left-to-right in landscape, where
                    // vertical space is scarcer - a Wrap (rather than a plain Row)
                    // still falls back to wrapping onto a second line instead of
                    // overflowing off-screen if all three don't fit on one. In
                    // portrait, the stack sits lower (bottom: 4 instead of 24) so
                    // its bottom edge lines up with the Google Maps zoom-out
                    // button in the opposite corner, rather than with the
                    // location-sharing button - landscape keeps 24 since the zoom
                    // controls sit differently there.
                    if (route != null)
                      Positioned(
                        bottom:
                            MediaQuery.of(context).orientation ==
                                Orientation.landscape
                            ? 24
                            : 4,
                        left: 92,
                        right: 24,
                        child: Wrap(
                          direction:
                              MediaQuery.of(context).orientation ==
                                  Orientation.landscape
                              ? Axis.horizontal
                              : Axis.vertical,
                          alignment: WrapAlignment.start,
                          spacing: 2,
                          runSpacing: 2,
                          children: [
                            _RouteMarkerLegend(
                              hasStops: route.waypoints.isNotEmpty,
                            ),
                            _RouteInfoChip(
                              icon: Icons.alt_route,
                              label:
                                  'Full route: '
                                  '${_formatDistanceDuration(route.distanceMeters, route.durationSeconds)}',
                            ),
                            if (_myEtaDuration != null &&
                                _myEtaDistanceMeters != null)
                              _RouteInfoChip(
                                icon: Icons.navigation,
                                label:
                                    'You: '
                                    '${_formatDistanceDuration(_myEtaDistanceMeters!.round(), _myEtaDuration!.inSeconds)}'
                                    ' to end'
                                    '${_myEtaRemainingStops > 0 ? ' ($_myEtaRemainingStops stop${_myEtaRemainingStops == 1 ? '' : 's'} left)' : ''}',
                              ),
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
                        backgroundColor: _sharing
                            ? Colors.red
                            : Colors.deepOrange,
                        tooltip: _sharing
                            ? 'Stop sharing my location'
                            : 'Start sharing my location',
                        child: Icon(
                          _sharing ? Icons.location_off : Icons.location_on,
                        ),
                      ),
                    ),
                  ],
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
      // Caps how wide this chip can grow - otherwise a long label (e.g. a
      // 3-digit mile count plus a stop count) can stretch far enough right
      // to sit under the Google Maps zoom-out button in the corner.
      constraints: const BoxConstraints(maxWidth: 220),
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
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Legend for the route markers' colors (start point, stops, destination) -
/// otherwise only distinguishable by tapping each one for its info window.
/// Colors are pulled from the same hues _buildRouteMarkers uses, so this
/// can never drift out of sync with the actual marker colors.
class _RouteMarkerLegend extends StatelessWidget {
  final bool hasStops;

  const _RouteMarkerLegend({required this.hasStops});

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
          _dot(BitmapDescriptor.hueGreen, 'Start'),
          if (hasStops) ...[
            const SizedBox(width: 10),
            _dot(BitmapDescriptor.hueAzure, 'Stop'),
          ],
          const SizedBox(width: 10),
          _dot(BitmapDescriptor.hueViolet, 'Destination'),
        ],
      ),
    );
  }

  Widget _dot(double hue, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colorForMarkerHue(hue),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }
}
