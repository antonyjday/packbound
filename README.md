# Convoy

Real-time location sharing for travel groups. Create a "convoy," invite people
by code, QR, or a `convoy://join/CODE` deep link, and see everyone's live
position on a shared map for the duration of the trip.

## Features

- **Anonymous sign-in** — just a display name, no accounts/passwords.
- **Create or join a group** — by 6-character invite code, QR code, or deep link.
- **Live map** — every member's position, heading, and speed, with per-member
  signal status (live / weak / lost based on how stale their last update is).
- **Background location sharing** — keeps reporting position while the app is
  minimized (Android foreground service / iOS background location mode).
  Starts automatically as soon as you open a group's map (still shown as a
  small toggle button, top-left alongside the other trip controls, if you
  want to pause it).
- **Trip lifecycle** — groups get a 24h hard-cap expiry (extendable by the
  owner), auto-end after 10h of inactivity, and get an in-app 4h/1h warning
  banner as the deadline approaches. Ended groups have their live location
  data wiped immediately; group metadata is purged after 30 days. Any
  member can leave at any time, including the owner - if the owner leaves
  while others remain, ownership automatically passes to whoever's been
  in the trip the longest, after an extra "are you sure?" warning. The
  owner can also remove any other member directly.
- **Shared trip route** — the owner taps a starting point (optional — defaults
  to their current location), a destination, and any planned stops right on
  the map; it's resolved into a real driving route (via the Directions API)
  and shown live to every member, along with the full-trip distance/ETA.
  Each member also sees their own live distance/ETA to the destination, and
  their own remaining path drawn as a second, dashed, member-colored line
  alongside the shared plan — so the route reflects where *they* actually
  are, not just where the owner was when they set it. A member who hasn't
  reached the trip's start point yet is routed there first, before the
  rest of the stops/destination, rather than straight past it — unless
  manually skipped: a skip-ahead button lets you push your own route past
  the start point, then each stop in turn, straight to the destination
  ("I'm not going to the meetup point, just route me onward"), and once
  fully skipped, pressing it again restores the full planned route.
  Joining a group with a route already set fits the camera to the whole
  planned trip (start point, waypoints, destination) alongside this
  device's own location; a route created/changed after that instead
  focuses the camera on just its new start point. A separate step button
  (flag icon, distinct from the arrow-style skip-ahead button next to it)
  lets you walk the camera (not your actual route) through each stop in
  order, then the destination, then
  your own current location, then back to the start. A dedicated "My
  location" button jumps the camera straight to your own current position
  on demand, separately from follow-mode. A search bar above these mode
  chips finds real addresses/places as you type (Places API) - picking a
  result sets whichever point the current mode means and jumps the map
  there, same as tapping the map itself would.
- **Turn-by-turn navigation** — a satnav-style bar at the top of the map
  showing your next maneuver (icon + instruction, e.g. "Turn left onto Elm
  St") and a live "in 0.3 mi" countdown. The instruction list comes from
  the same throttled per-device Directions call that already powers your
  personal ETA/route line, but which turn is "next" and its distance
  countdown are recomputed on every location update from simple proximity
  geometry - no extra API calls - so it keeps feeling live between those
  throttled refreshes. Own-device only, like the rest of your personal
  ETA/route. Instructions are phrased relative to *your* current heading,
  not compass direction - the Directions API itself only gives compass
  wording ("Head east on...") for a leg's very first step, since it has no
  prior direction to turn relative to yet; this app fills that gap from
  live GPS heading instead (e.g. heading south and needing to head east
  next reads "Turn left", not "Head east") - but only once moving fast
  enough for heading to be trustworthy, otherwise it falls back to the
  API's own wording.
- **Camera follow-mode** — the map re-centers on your own position while
  you're moving, satnav-style. Any manual look-elsewhere - dragging the
  map, picking someone from the roster, stepping through the trip's
  stops, or the owner setting a new route - pauses it for 30 seconds
  before it resumes following.
- **Offline awareness** — banner when the device loses connectivity.
- **Proactive push notifications** — the rest of the group gets a push
  (not just an in-app banner) when a member's location hasn't updated in
  5+ minutes ("Signal lost"), or when a member reaches the trip's
  destination ("Arrived"), so nobody has to be staring at the map to
  notice. Server-side (Cloud Functions), so it fires even if the app is
  backgrounded or killed.
- **Quick messages** — a one-tap button broadcasts a preset message
  ("Pulling over", "Need fuel", "Wait for me", ...) to the group - a
  centered alert dialog (with the preset's icon) for anyone with the map
  open, which stays up until explicitly acknowledged rather than a SnackBar
  that could come and go unread while someone's driving, plus a push
  notification for everyone else. Deliberately fixed presets rather than
  free-text chat, covering most real convoy communication needs for far
  less effort.
- **Low battery warning** — broadcasts a one-time warning (same alert-dialog/
  push pipeline as quick messages above) to the rest of the group the first
  time this device's own battery drops to 5% or below, so a dying phone
  isn't a silent surprise mid-trip.
- **Dark mode** — a manual toggle (map screen's menu), seeded from the
  device's own light/dark setting on first launch and persisted from then
  on. Covers the app's own theme, the Google Map's tiles (a separate night-
  style JSON, since the map doesn't follow Material theming on its own),
  and the route-planning screen's map/search bar.
- **Push-to-talk voice messages** — hold the mic button (bottom-right,
  above the zoom controls) to record, release to send. Shares the quick-
  messages feed/alert-dialog/push pipeline, auto-playing for the recipient
  as soon as their alert appears. Store-and-forward (a Firebase Storage
  upload + a Firestore doc), not live audio - chosen over a real-time
  WebRTC/vendor approach for far less effort at the cost of a few seconds'
  delivery delay, which doesn't matter much for short convoy call-outs.

## Tech stack

- **Flutter** (Android + iOS)
- **Firebase**: Auth (Anonymous), Firestore, Cloud Functions (group lifecycle)
- **Google Maps** (`google_maps_flutter`)
- **geolocator** / **permission_handler** for location
- **mobile_scanner** / **qr_flutter** for QR invites
- **app_links** for `convoy://join/CODE` deep links

## Project structure

```
lib/
  models/       ConvoyGroup, LocationPoint
  screens/      sign-in, home, map, invite, QR scan, permission explainer
  services/     auth, group, location, deep-link
functions/      Cloud Functions — group expiry/cleanup (see CLEANUP.md)
firestore-tests/ firestore.rules test suite (Node, against the real emulator)
```

## Getting started

1. `flutter pub get`
2. This app is already linked to the `convoy-app-ajd` Firebase project
   (`lib/firebase_options.dart`, `android/app/google-services.json`). If you
   need to point it at a different project, run `flutterfire configure`.
3. `flutter run` (Android emulator/device — see `flutter emulators` if you
   don't have one set up).

For Android/iOS-specific setup (Maps API keys, background location
entitlements, deep link wiring) see [PLATFORM_SETUP.md](PLATFORM_SETUP.md).
For how the group expiry/cleanup Cloud Functions work and how to deploy them,
see [CLEANUP.md](CLEANUP.md).

## TODO

**Done:**
- [x] Cloud Functions deployed and active (`trackGroupActivity`,
      `endInactiveGroups`, `warnExpiringGroups`, `cleanupEndedGroupData`,
      `purgeOldEndedGroups`) — group expiry/cleanup now actually runs.
- [x] Verified real multi-device location sharing end-to-end on two Android
      emulators: create group, join by invite code, live positions on both
      maps, roster names.
- [x] Fixed: group creation was completely broken
      (`cloud_firestore/permission-denied` on every "Create group" tap) — the
      owner-membership write and the group-doc write were in the same
      WriteBatch, but the membership rule's `get()` can't see a sibling
      write from the same batch, so it always got denied. Now two sequential
      writes.
- [x] Fixed: map markers and the member roster showed blank names — the
      name entered at sign-in was saved to Firestore but never set on the
      Firebase Auth profile, which is what those views actually read.
- [x] Member markers now get a distinct, consistent color per user (instead
      of color meaning signal status, which made every "live" member look
      identical). Signal status is now shown via marker opacity instead.
      The roster's avatar uses the same color as its member's marker, acting
      as a legend without extra UI on the map itself.
- [x] Fixed: Set route screen opened on a zoomed-out world view, since it
      relied on `getLastKnownPosition()`, which is frequently unpopulated.
      Now actively fetches a fresh position up front (briefly showing a
      loading spinner) and opens already centered ~9 zoom (roughly a 50mi
      radius) on the owner's current location; still falls back to the world
      view only if location permission truly isn't available.
- [x] Fixed: live "my ETA" always routed straight to the final destination,
      ignoring waypoints entirely. Now routes through whichever waypoints
      haven't been reached yet (a proximity check against each waypoint in
      order - anything within 500m is treated as passed), and the chip shows
      how many stops remain. It's a simple recomputed-fresh heuristic, not
      persisted "visited" state, so it self-corrects if someone backtracks.
- [x] Push notifications for trip-expiry warnings — `NotificationService`
      registers each signed-in device's FCM token onto `users/{uid}.fcmToken`,
      and `warnExpiringGroups` now pushes to every group member (matching who
      already sees the in-app banner) when a trip crosses the 4h/1h warning
      thresholds. **Android only for now** — iOS has no Firebase/APNs config
      yet (see below).
- [x] Fixed a pre-existing bug found while wiring up the above:
      `warnExpiringGroups` had been failing on *every single run* since it was
      first deployed (`FAILED_PRECONDITION: The query requires an index`) —
      the composite index in `firestore.indexes.json` had `tripExpiresAt` and
      `expiryWarningLevel` in the wrong order relative to what the query
      actually needed. This silently broke the entire expiry-warning feature,
      including the in-app banner, not just the new push - `expiryWarningLevel`
      was never being set. Fixed and confirmed via `firebase functions:log`
      that the sweep now runs clean.
- [x] Added a first batch of automated tests (`flutter test`, 33 tests, no
      new dependencies) covering pure Dart logic: `LocationPoint`'s
      live/weak/lost signal-status thresholds and `lastSeenLabel` formatting,
      `extractInviteCode`/`buildInviteLink`, `decodePolyline`, member marker
      color assignment (determinism + no collision with the reserved route
      marker hues), and `RouteStop`/`RoutePlan` map round-tripping.
      Deliberately scoped to logic with no Firebase dependency for now -
      `GroupService`/`AuthService` (need `fake_cloud_firestore` +
      `firebase_auth_mocks` mocking) and `firestore.rules` itself (needs
      the emulator + `@firebase/rules-unit-testing`, a separate Node test
      suite - the only thing that would've caught the group-creation
      batch/rules bug from earlier) are follow-ups below.
- [x] Updated tests for the route/lifecycle features added in the other
      session (46 tests total now). Along the way, extracted `MapScreen`'s
      private `_remainingLegs` into a standalone, testable
      `remainingLegs()` in the new `lib/utils/route_progress.dart` (same
      logic, just explicit parameters instead of implicit `this.` reads) -
      and writing real test cases for it surfaced a genuine bug: it walked
      legs (start point, then waypoints) in order and stopped at the
      *first* one further than the 500m arrival radius, so once a member
      had driven past the start point (almost immediately - it's the very
      first leg), every later recalculation found the start point still
      "far" and broke immediately, never even checking whether the member
      had also reached waypoint 1, waypoint 2, etc. In practice this meant
      a member's live route/ETA got stuck always routing back through
      already-passed legs instead of dropping them. Fixed by checking every
      leg and taking the *last* (highest-index) one within radius, rather
      than stopping at the first one outside it - `ConvoyGroup`'s new
      `ownerId` field also got a small round of coverage while in here.
- [x] Fixed: the shared route was drawn identically for every member, from
      wherever the owner was when they set it - a member miles away from
      that path had no way to see their own way to the destination. Each
      viewer's map now also draws their own remaining route (dashed, in
      their marker color), reusing the polyline from the same throttled
      per-member Directions call that already powered the "my ETA" chip -
      no extra API calls. Applies equally to the owner's own device, not
      just other members.
- [x] Set/edit route screen: the starting point can now be picked on the
      map (a "Start" mode alongside Destination/Add stop), defaulting to the
      owner's current location at save time if left unset - useful for
      planning a trip ahead of time from somewhere other than wherever the
      owner currently is.
- [x] Location sharing now starts automatically on opening a group's map,
      instead of requiring a manual tap every time (it was never persisted
      across screen visits) - the button remains, now a small circular FAB
      instead of a full-width bar, both to make manual pause/resume quicker
      and because the old bar overlapped Google Maps' zoom controls.
- [x] Fixed: opening a group with a route already set (or having one just
      created) showed the old "fit everyone plus the destination/stops"
      camera view, which could land far from where the trip actually
      starts. Now centers on the route's start point first instead. Added
      a step-through button (top-right, next to roster/re-fit) that walks
      the camera to the first stop, then each subsequent stop, then the
      destination, then this device's own current location, then wraps
      back to the start.
- [x] Fixed: a member's live route/ETA routed straight from their current
      position to the next stop or the destination, skipping the trip's
      start point entirely even if they hadn't reached it yet. The start
      point is now treated as this member's first leg, same proximity-based
      "already passed" logic as any other stop - so someone who hasn't
      convened at the start yet is routed there first, not past it.
- [x] Added a skip-ahead button (top-right, next to the step-through
      button) that manually forces a member's own route/ETA past legs it
      would otherwise still route them to, one at a time: start point
      first, then each waypoint in order. Once every leg is skipped (routing
      straight to the destination), pressing again resets it, restoring the
      full planned route. Unlike the step-through button, this changes the
      actual route/ETA and dashed line, not just the camera, and recalculates
      immediately rather than waiting for the next throttled tick.
- [x] Fixed: joining a group with a route already set jumped straight to a
      tight zoom on just the start point, without showing the waypoints,
      destination, or this device's own location - the start-point focus is
      now reserved for a route being created/changed *after* the initial
      join view, which instead fits the camera to the whole planned trip
      (start point, waypoints, destination) and this device's own location
      together, same as joining a group with no route set yet does for
      just the members. Also fixed the route bounds themselves to include
      the start point, which they'd never done even before this change.
- [x] Added a marker for the route's start point on the live map screen
      (previously only marked while planning in SetRouteScreen, not once
      the route was actually live) - green, matching SetRouteScreen's own
      start marker. Reserved `hueGreen` for it in `member_colors.dart`,
      shrinking the member color palette by one to keep the existing
      guarantee that a member's marker color is never confused with a
      route marker's.
- [x] Added a legend for the start/stop/destination marker colors (a small
      chip near the route info, above "Full route: ..."), since they were
      previously only distinguishable by tapping each one for its info
      window. Colors are pulled from the same hues `_buildRouteMarkers`
      uses, so it can't drift out of sync with the actual marker colors.
- [x] Added owner ability to remove a member from the convoy - a remove
      button in the roster (owner-only, hidden on the owner's own row)
      that, after confirming, deletes both the member's membership doc and
      their live location doc (so their marker disappears immediately
      rather than lingering as a stale pin). Needed a `firestore.rules`
      change to let the owner delete another member's location doc -
      deployed to the live project.
- [x] Added graceful handling on the *removed* member's own device: a new
      listener on their own membership doc detects it being deleted,
      immediately stops location sharing (rather than letting the next
      write silently fail with permission-denied), shows a dialog telling
      them they've been removed, and sends them back to the home screen
      once acknowledged.
- [x] Added a "Leave trip" button for every member, including the owner
      (`GroupService.leaveGroup` - previously written but never wired up
      to any UI). An owner leaving while other members remain gets an
      extra warning-then-"are you sure?" pair of dialogs instead of the
      single confirmation everyone else gets, since ownership then
      automatically passes to whichever remaining member has been in the
      trip the longest (earliest `joinedAt`) before the leaving owner's
      own membership is removed - the update rule for changing another
      member's role requires the caller to still be owner at the time of
      the write, so the promotion has to happen first. Marks the removal
      as self-initiated before deleting the membership doc, so the
      removed-member listener above doesn't also show its "you were
      removed" dialog for this voluntary leave.
- [x] Fixed: a non-owner member leaving got a Firestore permission-denied
      error - `firestore.rules` only ever let the *owner* delete a
      `members` doc, never a member deleting their own (owner-initiated
      removal and owner-leaving both happened to work already, since the
      caller was still recognized as owner at the time of that delete).
      Split the `update, delete` rule so delete also allows
      `request.auth.uid == memberId`. Also reordered `leaveGroup` to
      delete the location doc *before* the membership doc, since the
      locations write rule requires still being a member at that moment -
      deleting membership first would've made that best-effort cleanup
      silently fail too. Deployed to the live project.
- [x] Fixed: when ownership passed to a successor (owner leaves, other
      members remain), the successor's own app didn't reflect their new
      privileges - `_isOwner` was only ever set once, from a one-off
      fetch in `initState`, so a role change after the map screen was
      already open (exactly what happens on a live handoff) went
      unnoticed and their menu stayed stuck on member-only options. Folded
      the ownership check into the existing live membership-doc listener
      (previously only used to detect removal) instead of a separate
      one-time `_checkOwnership()` call, so `_isOwner` now updates in
      real time same as everything else derived from that doc.
- [x] Added a snackbar telling the successor when ownership hands off to
      them - the menu unlocking new options above wasn't obvious on its
      own. Only fires on a genuine transition (not on first opening the
      map screen already as owner), by comparing against the *previous*
      `_isOwner` value before the membership listener overwrites it.
- [x] Added a persistent purple banner ("You're the owner of this trip")
      at the top of the map whenever `_isOwner` is true - the one-off
      handoff snackbar above only covers the moment ownership changes,
      not an ongoing reminder of whose settings/route changes actually
      apply while looking at the map generally.
- [x] Added ownership inheritance for abandoned trips: if everyone leaves
      a group, including the owner, the next person to rejoin via invite
      code now inherits ownership instead of joining as an ordinary
      member with no owner around. Needed a denormalized `ownerId` field
      on the group doc (kept in sync with the members subcollection's
      role, alongside `createdBy` which never changes) since
      `firestore.rules` can't check "is the members subcollection empty"
      directly - `null` means ownerless. The rejoin-and-claim is wrapped
      in a transaction so two people racing to rejoin at once can't both
      end up claiming it. Deployed the updated rules to the live project.
- [x] Fixed: rejoining a group (including the ownerless-rejoin case just
      above) incorrectly showed the "removed from convoy" dialog right
      after rejoining. A Firestore local-cache quirk: the first snapshot
      on a *new* membership-doc listener can momentarily read a stale
      "not found" - a tombstone left over from the old, just-deleted
      membership doc - before the fresh "exists" snapshot for the new
      membership arrives. The removed-member check now only reacts to a
      doc disappearing *after* membership has already been confirmed to
      exist at least once, not on a screen's very first snapshot.
- [x] Fixed: the group-doc and membership-doc listeners in `map_screen.dart`
      had no `onError` handler, so a permission-denied after leaving/being
      removed (expected - this device is no longer a member, so it loses
      read access to both) surfaced as an unhandled exception instead of
      being silently ignored. Found while investigating repeated
      permission-denied errors logged during aggressive join/leave testing
      between two devices.
- [x] Fixed the real bug behind "removing a member doesn't do anything on
      their own device": reading your OWN membership doc requires
      `isMember(groupId)`, which itself depends on that exact doc's
      existence - so the moment it's deleted (owner removed you, or you
      left), Firestore reports a `PERMISSION_DENIED` **error** on that
      listener, not a graceful "document doesn't exist" data event. The
      `onError` handler added just above was silently swallowing exactly
      this signal instead of treating it as "you've been removed" -
      `_membershipSub`'s `onError` now calls the same removal handling
      the (rarely-hit) `doc.exists == false` path uses.
- [x] Fixed a second bug found while verifying the above on real devices:
      `joinGroupByInviteCode` unconditionally overwrote the member doc
      based only on whether the group was currently ownerless, with no
      check for "am I already a member?" - so simply re-entering an
      invite code you'd already joined with (e.g. after the app restarts
      and loses its "which group am I in" navigation state) could
      silently demote an existing owner back to an ordinary 'member'.
      Now a no-op if the member doc already exists. Needed a
      `firestore.rules` change too: checking "do I already have a member
      doc" requires reading it, but the read rule required already being
      a confirmed member - a chicken-and-egg permission-denied for anyone
      joining fresh. The read rule now also allows any signed-in user to
      read (only) their own potential doc regardless of whether it
      exists yet. Deployed to the live project.
- [x] Gave the map screen more room, in a few steps, tested on-device after
      each: the route info stack (marker legend, full-route chip, "you"
      chip) now lays out left-to-right in landscape via a `Wrap` instead of
      staying stacked top-to-bottom (the landscape gap called out below);
      that stack also moved from spanning the bottom of the map to sitting
      beside the location-sharing button, tightened up, and - in portrait -
      bottom-aligned with the Google Maps zoom-out button rather than the
      location button; the app bar shrank from the default 56 to 40 with
      tightened action buttons; and the persistent purple "You're the
      owner of this trip" banner was replaced with a compact star + "Owner"
      label inline in the app bar, next to the menu button.
- [x] Fixed the "you" ETA chip (bottom-right route info stack) growing wide
      enough to sit under Google Maps' own zoom-out button when its label
      got long (long distance + duration + a remaining-stop count) - it's
      now capped at 220px wide with ellipsis truncation, and the label
      itself was shortened from "to destination" to "to end".
- [x] Hardened `tool/simulate_trip.mjs` (the manual multi-participant
      simulation script) after running it end-to-end for the first time
      surfaced two gaps: it only ever reinstalled the debug APK on the
      headless second emulator, so the visible emulator silently kept
      running whatever build happened to already be on it (this is what
      made the zoom-control overlap above look like a live app bug rather
      than a stale install); and it had no handling for a real first-run
      sign-in screen (a brand-new emulator/AVD has no persisted anonymous
      Firebase session), so a fresh headless emulator's deep-link join
      would just time out sitting on that screen. Both fixed: the visible
      emulator now gets the same `adb install -r` + permission pre-grants
      as the headless one before joining, and a new `ensureSignedIn` step
      automates the name-entry screen when present (re-reading the UI
      layout after typing, since the on-screen keyboard shifts it).
- [x] Added the turn-by-turn navigation bar and camera follow-mode
      described above. `DirectionsService` now parses each step's
      instruction/maneuver/distance/start+end location (previously it only
      kept the overall polyline/distance/duration); `RouteStep` and the new
      `lib/utils/navigation_progress.dart` (nextNavigationStep,
      classifyTurnManeuver, relabelHeadInstruction, maneuverIcon) are
      covered by `test/utils/navigation_progress_test.dart`, since the
      Android emulator's mock GPS (`adb emu geo fix` and `geo nmea` both,
      confirmed via `dumpsys location`) never actually reports a nonzero
      speed/bearing in this environment - `geo gnss` exists but needs raw
      satellite pseudorange data, not a usable substitute - so the
      heading-relative relabeling and follow-mode's "am I moving" check
      couldn't be exercised live and were instead verified by dedicated
      unit tests covering the classification boundaries directly. Manually
      confirmed live: the nav bar itself renders/updates correctly, and the
      camera-jump regressions (step-through, roster select) still work
      after routing all camera moves through the new `_animateCamera`
      wrapper. A real device's GPS reports genuine speed/heading, so both
      features should engage normally there.
- [x] Gated the owner-only "Extend trip 24h" menu item to only appear once
      under 12h remain (`extendEligibleLead` in `map_screen.dart`), instead
      of being offered any time the trip hasn't ended. Also verified
      end-to-end (previously just a code-inspection claim) that
      `GroupService.extendTrip` genuinely resets `tripExpiresAt` to 24h
      from the moment of the button press rather than compounding onto
      whatever time was already left: tapped it for real (temporarily
      raising the threshold to exercise the button, then reverting)
      against a group with ~23.5h already left, and confirmed via a direct
      Firestore read that the new deadline landed at exactly
      tap-time + 24h, not old-deadline + 24h (which would have been ~48h
      out).
- [x] `createGroup` now checks a freshly generated invite code against
      other *active* groups before writing (`GroupService._generateUniqueInviteCode`,
      retrying up to 5 times) - previously it never checked at all,
      meaning `joinGroupByInviteCode`'s `.limit(1)` lookup could
      non-deterministically route a joiner to the wrong group in the
      astronomically unlikely event two active groups collided. Verified
      end-to-end by seeding a real colliding active group in Firestore,
      temporarily forcing the generator to draw that exact code on its
      first call, and confirming the app's own "Create group" flow
      retried and returned a different, uncollided code rather than the
      seeded one.
- [x] Made the trip-camera buttons clearer: the "step through trip" button
      now uses a flag icon (`Icons.tour`) instead of `Icons.skip_next`,
      which read as a near-duplicate of the "skip ahead" button's
      fast-forward/restore arrows right next to it. Also added a dedicated
      "My location" button (`Icons.my_location`) that jumps the camera
      straight to this device's own position on demand - distinct from
      both the "fit everyone" refit button and follow-mode (which only
      re-centers automatically while moving): unlike every other manual
      camera button, it deliberately does *not* pause follow-mode
      afterward, since recentering on yourself is exactly what follow-mode
      already does.
- [x] Added route search/autocomplete (`PlacesService`, new
      `lib/models/place_suggestion.dart`), via the Places API (New) -
      same bespoke REST-call style as `DirectionsService` rather than
      pulling in a places-picker package, and same Android-restricted
      Maps key, now also allow-listed for this API. Uses a real session
      token (`PlacesService.newSessionToken`) shared across one search's
      autocomplete keystrokes and its eventual place-details lookup, since
      Google bills that as a single session rather than per-request.
      Getting this live took two Google Cloud setup steps beyond just
      writing the code: enabling "Places API (New)" for the project
      wasn't enough on its own - the Maps API key also had an API
      restrictions allowlist that needed "Places API (New)" added to it
      separately (same class of gotcha as the earlier Maps SHA-1
      restriction issue). Verified end-to-end on-device once both were
      done: typed "London", picked a suggestion, and confirmed the
      destination pin landed exactly on central London.
- [x] Moved the location-sharing toggle from bottom-left to top-left, in
      line with the roster/refit/recenter/step/skip row on the right -
      grouping every trip control along one row reads more clearly than
      splitting them across two corners. The route-info chip stack at the
      bottom, previously indented (`left: 92`) to leave room for the
      button that used to sit there, now starts flush at `left: 24` too.
- [x] Added the two proactive push notifications described above
      (`functions/src/index.ts`): `notifyLostSignals` is a scheduled sweep
      (every 5 min) using a `collectionGroup('locations')` query across
      every group at once - a location doc surviving at all implies its
      group is still active, since `cleanupEndedGroupData` already wipes
      a group's locations the moment it ends, so no per-group status
      check is needed. `notifyOnArrival` is a plain Firestore trigger on
      the same `locations/{userId}` writes `trackGroupActivity` already
      reacts to. Both write a marker on the location doc tied to the
      value that would change if the condition should fire again
      (`signalLostNotifiedForUpdatedAt` compared against the location's
      own `updatedAt`; `arrivedNotifiedForRouteSetAt` compared against
      the group's `route.setAt`) rather than a plain boolean, so a fresh
      location update or a new route naturally re-arms the check without
      a separate "reset" pass. `sendExpiryWarningPush`'s token-fetching
      was extracted into a shared `sendPushToGroupMembers` helper both
      new functions reuse. Needed a new `locations.updatedAt` field
      override in `firestore.indexes.json` (`queryScope:
      COLLECTION_GROUP`) for the sweep's query - a composite index
      wasn't the right tool here; Firestore rejected that with "this
      index is not necessary, configure using single field index
      controls" until it was expressed as a field override instead.
      Verified both live end-to-end on-device: seeded a script-controlled
      test member's location at the exact destination coordinates and
      watched the real "Arrived" push land in the notification tray, then
      (temporarily lowering the sweep interval/threshold to make the
      already-stale test doc trigger immediately, reverted after) watched
      "Signal lost" land the same way.
- [x] Added `GroupService`/`AuthService` tests (25 tests, 89 total now) -
      the Firebase-dependent half deferred from the first test batch
      above. Needed `GroupService`/`AuthService` to accept an optional
      injected `FirebaseFirestore`/`FirebaseAuth` instance (defaulting to
      the real singletons, so every existing call site is unaffected) so
      tests can hand them a `fake_cloud_firestore`/`firebase_auth_mocks`
      instance instead. Covers `createGroup`, the full
      `joinGroupByInviteCode` matrix (fresh join, ownerless-group
      inheritance, expired/invalid codes, ended-group codes) including
      regression tests for the two real bugs fixed earlier this project
      (re-entering your own invite code demoting you from owner; the
      members-read chicken-and-egg permission issue that fix caused),
      `leaveGroup`'s successor-promotion and ownerless-clearing paths,
      `removeMember`, and `extendTrip`'s reset-not-compound behavior.
      `mocktail` was pulled in as a dependency for this but ended up
      unused - `fake_cloud_firestore`/`firebase_auth_mocks` covered
      everything needed, so it was removed again rather than left
      unused. The remaining half of the original TODO - a `firestore.rules`
      test suite against the real emulator - is still open, see below
      (mocked-Firestore tests don't enforce actual security rules, so
      they can't catch the class of bug that motivated this in the first
      place).
- [x] Added a `firestore.rules` test suite (`firestore-tests/`, 45 tests -
      grew from the initial 38 once the `messages` rules were added)
      against the real Firestore emulator via
      `@firebase/rules-unit-testing` - a separate Node project from
      `functions/` (this tests the rules themselves, not the Cloud
      Functions) using Node's built-in test runner rather than adding a
      new framework dependency. Run with:
      `firebase emulators:exec --only firestore "cd firestore-tests && npm test"`
      from the repo root (needs `npm install` in `firestore-tests/`
      first, and Java 21+ for the emulator itself - this environment only
      had Java 17 installed for the Android toolchain, so Temurin 21 was
      installed alongside it via `winget`). Covers every branch of every
      rule: the `users` doc read/write split, `groups`' create/delete/
      update including the narrow ownerless-ownership-claim exception
      (accepted only when it touches *just* `ownerId` and the group was
      actually ownerless; rejected if it touches other fields, claims
      ownership for someone else, or the group already has an owner),
      and the full `members`/`locations`/`messages` matrices - including a
      regression test for the exact chicken-and-egg member-read fix from
      earlier (a non-member can read their own not-yet-existing member
      doc, but not anyone else's). This is what the mocked-Firestore
      service-layer tests above structurally can't do, since a fake
      Firestore doesn't evaluate `firestore.rules` at all. Re-verified
      passing (all 45) after later rules-adjacent changes (member removal,
      ownership inheritance, quick messages) with no drift.
- [x] Added quick messages (described above): new `GroupMessage` model,
      `groups/{groupId}/messages` subcollection (`GroupService.
      sendQuickMessage`/`messagesStream`), a `notifyOnQuickMessage` Cloud
      Function reusing the same `sendPushToGroupMembers` helper the other
      notifications use, and matching `firestore.rules` (send-as-yourself/
      member/active-group guards mirroring `locations`, no update/delete -
      an immutable fire-and-forget log) with 7 new rules tests (45 total
      now) and 2 new service tests (91 Dart tests total). Wired the
      incoming-message listener the same way `_groupStatusSub`/
      `_membershipSub` already work - a live subscription outside
      `build()`, not a StreamBuilder, since it's a side-channel event feed
      (pop a SnackBar) rather than something the map needs on every frame.
      `cleanupEndedGroupData` now also purges `messages` when a group
      ends, alongside `locations`. Verified live end-to-end: sent "Pulling
      over" from the app and confirmed the Firestore doc; separately
      confirmed a real push ("TestScriptMember: Need gas") landing on a
      backgrounded device from a script-simulated sender, same
      verification approach used for the other notifications above (one
      of the two test emulators repeatedly hit an unrelated System UI
      crash loop this session, so the foreground SnackBar path is only
      verified by code inspection/pattern-matching against the already-
      proven signal-lost/back-online SnackBar, not a live screenshot).
- [x] Fixed the shared route's drawn polyline cutting corners on long
      trips (reported: a 1400-mile cross-continental trip's turn-by-turn
      banner was correct but the drawn line looked rough/imprecise when
      zoomed in). Root cause: `DirectionsService` built the drawn polyline
      from the Directions API response's `overview_polyline` - a
      deliberately simplified/smoothed path, fine for a short hop but only
      1274 characters for a real ~1100mi test route, vs. ~195,000
      characters across that same route's per-step polylines (each step
      already being parsed anyway, for the turn-by-turn instructions -
      just not its own `polyline` field). Now decodes and concatenates
      every step's own polyline instead of using the coarse overview one,
      added `encodePolyline` (the reverse of the existing `decodePolyline`)
      to re-encode the combined precise path back into the single stored
      polyline string, with 3 new tests (94 Dart tests total). Verified
      against real Directions API data first (confirmed the 1274 vs
      ~195,000 character gap on an actual London→Rome route), then live
      on-device: saved that same London→Rome route and confirmed the
      drawn line now precisely hugs a road's curve (Victoria Embankment
      near Charing Cross) rather than approximating across it.
- [x] Widened the bottom-left route-info chips (`_RouteInfoChip`'s
      `maxWidth`, 220 -> 300) now that they have more room to work with -
      the container itself was already widened when the location-sharing
      button moved to the top (see above), but the chips' own per-chip cap
      (unrelated, originally sized to avoid the Google Maps zoom-out
      button specifically) was still the actual limiter, so they weren't
      using the freed-up space. Verified live: the "You: ... to end (1
      stop left)" chip on a long route now shows in full with no
      ellipsis, with a comfortable gap before the zoom +/- controls.
- [x] API billing efficiency pass. Directions and Places were already
      well-throttled (2min/300m gate on live ETA recalcs, 350ms debounce +
      session tokens + a minimal field mask on autocomplete); the real
      lever was Firestore: `LocationService.startSharing`'s position stream
      wrote on every 10m/3s movement, and since every other member has a
      live listener on that subcollection, cost scales as writes ×
      (members − 1) — the single biggest volume driver on a long multi-
      member trip. Loosened to 25m/6s (imperceptible for a convoy's pace,
      given ETA already only recalculates every 2 minutes regardless).
      Also added a 2-character minimum before firing autocomplete, to skip
      billed calls on prefixes too short to be useful.
- [x] Reworked incoming quick messages from a SnackBar to a centered
      `AlertDialog` (`barrierDismissible: false`, with the preset's icon)
      that stays up until the recipient taps OK - reported as "not
      particularly clear, especially if someone is driving". Alerts queue
      (`_pendingMessageAlerts`) and show one at a time so several messages
      in quick succession don't stack or get lost. While in there, fixed a
      real (pre-existing, not introduced by this change) bug in
      `_onMessagesSnapshot`: the `messages.isEmpty` early-return ran before
      the `_hasSeenMessages` gate, so a brand-new group's genuinely-empty
      first snapshot never armed that gate - meaning the very first real
      message anyone ever sent in a group got mistaken for the
      pre-existing-messages baseline and silently swallowed instead of
      shown. Verified live on two emulators: first message in a fresh
      group now alerts correctly, and the dialog stays up until
      acknowledged.
- [x] Added a per-member low-battery warning: `MapScreen` checks this
      device's own battery (`battery_plus`) every 2 minutes (plus once on
      open), and the first time it's at or below 5%, broadcasts a warning
      to the rest of the group through the same quick-message pipeline
      (`GroupService.sendQuickMessage`) - so it shows as the same centered
      alert dialog/push notification, with a battery icon, rather than a
      separate notification path. Fires once per session
      (`_lowBatteryWarned`, only set once the send actually succeeds so a
      transient failure gets retried on the next tick) and never on the
      low-battery device's own screen (same as a sender never seeing their
      own quick message). Verified live on two emulators.
- [x] Added dark mode: `ThemeService` (a single global
      `ValueNotifier<ThemeMode>`, persisted via `shared_preferences` -
      deliberately just light/dark, not a three-way system/light/dark
      picker) wired into `MaterialApp`'s `darkTheme`/`themeMode`, with a
      "Dark mode" toggle in the map screen's menu (same checkbox style as
      "Allow members to invite"). Considered auto-switching at the user's
      local sunset/sunrise first, but that needed the same dark-theme
      groundwork anyway plus its own extra state (recheck on
      resume/at the sunset boundary, still needing a manual override) for
      comparatively little gain over a plain toggle, so built the toggle
      first. Since the Google Map doesn't follow Material theming on its
      own, added `lib/utils/map_styles.dart` (a night-mode style JSON) and
      apply it to `GoogleMap`'s `style` property on both the main map and
      the route-planning screen. Also caught (from live testing) the
      route-planning screen's search bar, which had a hardcoded
      `fillColor: Colors.white` left over from before dark mode existed -
      switched to `Theme.of(context).colorScheme.surface`. Verified live:
      toggle switches the whole app immediately (chrome, both maps,
      search bar), and the choice survives a full app restart.
- [x] Added push-to-talk voice messages: `VoiceMessageService` (`record`
      for capture, `firebase_storage` for upload, capped at 30s) plus a
      hold-to-record mic button (bottom-right, above the zoom controls -
      moved there from the top button row and enlarged after live
      feedback). Deliberately store-and-forward rather than live audio -
      considered first since it needed no new real-time infrastructure,
      reusing the entire quick-messages pipeline instead: `GroupMessage`
      gained optional `audioUrl`/`audioDurationSeconds` fields
      (`isVoice` getter), `GroupService.sendVoiceMessage` writes to the
      same `messages` subcollection, `notifyOnQuickMessage` sends "🎤 Voice
      message" as the push body when `audioUrl` is set, and the receiving
      alert dialog auto-plays the clip (`just_audio`) as soon as it
      appears rather than requiring an extra tap. Required enabling
      Firebase Storage for the first time on this project (previously
      unused) and a new `storage.rules`.
      Root-caused two real bugs during live testing: (1) a genuinely
      hung-forever upload traced to a wrong assumption about the bucket
      name (a red herring - the bucket name is an opaque identifier, not
      a literal resolvable hostname, so the original DNS-based diagnosis
      was wrong and had to be reverted); (2) storage.rules' cross-service
      `firestore.get()`/`exists()` membership check reliably denies even
      a real member on this project (isolated via a controlled REST test:
      an equivalent rule with no Firestore call passes instantly, the
      same rule gated by `firestore.get()` doesn't) - looks like a
      platform/IAM-level gap rather than a rules-syntax bug, so
      `storage.rules` falls back to `request.auth != null` (matching the
      bar `groups/{groupId}` already uses in `firestore.rules`) rather
      than member-scoping. `cleanupEndedGroupData` also now deletes a
      group's voice clips from Storage when the group ends, alongside the
      existing Firestore purge. Verified live end-to-end via REST
      (upload + read-back) and on-device (record → alert dialog → auto-
      play on a second device).
- [x] The QR scanner (`scan_qr_screen.dart`) showed a bare `Icons.error`
      with zero detail whenever the camera failed to start on a real
      device - reported as "just an exclamation mark in a circle" after
      granting camera permission. `mobile_scanner`'s default error view
      doesn't surface anything from the underlying
      `MobileScannerException`; added an `errorBuilder` that shows the
      actual error code/message. That surfaced the real error on retry:
      `genericError` - `Attempt to invoke virtual method
      'java.lang.Class java.lang.Object.getClass()' on a null object
      reference`, a known class of camera-init bug in older
      `mobile_scanner` releases. Upgraded `mobile_scanner` 5.2.3 → 7.4.0
      (only breaking change hit: `errorBuilder` dropped its third `child`
      parameter). Verified fixed on the real device that hit the original
      crash - QR scan now works.
- [x] Fixed two real-device issues found during testing:
      1. Members standing still got wrongly marked "signal lost" - the
      `distanceFilter`-based position stream (see the API-efficiency pass
      above) produces zero events at all while stationary, so
      `updatedAt` goes stale and trips `SignalStatus.lost` after just 60s
      (`LocationPoint.status`) even though the member is still actively
      sharing. Added a 20s heartbeat timer in `LocationService` that
      re-sends the last known position regardless of movement, comfortably
      under both that 60s client-side cutoff and the server-side
      `notifyLostSignals` sweep's 5-minute one.
      2. The phone auto-locked mid-trip, worse than a normal nav app since
      a stationary/idle device has no touch input to reset the screen
      timeout either. Added `wakelock_plus`, enabled only while `_sharing`
      is actually on (toggled via a new `_setSharing` helper covering all
      four places sharing turns on/off), not for the whole time the map
      screen is open.
- [x] The top-right button row (roster/refit/"My location"/step-route/
      skip-route, up to 5 buttons) was laid out horizontally via
      hardcoded `right: 12/68/124/180/236` - fine at normal density, but
      reported as buttons "stacked on top of each other" on a smaller
      device or with Android's "Display size" accessibility zoom setting
      turned up (both effectively shrink the usable logical-pixel width).
      Switched to a vertical stack down the right edge (same `right: 12`,
      `top: 12/68/124/180/236` instead) - portrait phones have far more
      vertical slack than horizontal, so this sidesteps the width
      constraint entirely rather than fine-tuning pixel offsets. Verified
      by reproducing the exact scenario: bumped emulator density from
      420 to 560 (`adb shell wm density 560`, matching a "Display size"
      zoom bump) - confirmed all 5 buttons stack cleanly with no overlap.

**Needed before this is usable end-to-end:**
- [ ] iOS Firebase config — `flutterfire configure` didn't produce a
      `GoogleService-Info.plist` (needs to be regenerated, ideally from a Mac
      with Xcode installed). iOS hasn't been built or run at all yet.
- [ ] iOS Google Maps API key — still a placeholder in `AppDelegate.swift`.
- [ ] Release signing — the current Android Maps API key is restricted to the
      debug keystore's fingerprint only. Generate a release keystore and add
      its SHA-1 to the key's restrictions (or create a separate release key)
      before shipping a release build.

**Known gaps / follow-ups called out in the code:**
- [ ] Custom URL scheme (`convoy://`) only works if the app is already
      installed. Upgrading to a universal/app link
      (`https://yourdomain.com/join/CODE`) would let invites degrade
      gracefully for people who don't have the app yet — needs a real domain
      and hosting `.well-known/apple-app-site-association` /
      `assetlinks.json`. See PLATFORM_SETUP.md for details.
- [ ] `applicationId`/bundle ID are still the Flutter-generated
      `com.example.convoy.*` — rename before publishing to either app store.
- [ ] No app icon / launch screen customization — using Flutter defaults.

**Future feature ideas (not started):**
- [ ] In-app group voice call — a button to join a live audio call with
      everyone currently in the convoy. Push-to-talk (see "Done" above)
      covers the "quick call-out" case with far less effort by staying
      store-and-forward; this would be the genuinely live/simultaneous
      version, a real capability class jump (live media), not an
      extension of anything currently in the app.
      Realistic path: a managed service (LiveKit, Agora, etc.) via its
      Flutter SDK, with a small Cloud Function to mint join tokens and a
      join/leave/mute UI (~3-5 days) - handles multi-party audio mixing
      and NAT traversal for you, at the cost of a per-minute-billed
      vendor dependency. Raw WebRTC with Firestore as a signaling channel
      avoids that vendor but needs a self-hosted TURN server and hits a
      real quality ceiling past ~4-6 simultaneous speakers (mesh
      topology), for meaningfully more effort and ongoing ops burden.
- [ ] Ambient per-member battery-level visibility (Life360/Find My both
      show this) - a one-time 5%-or-below warning already exists (see
      "Done" above), but there's still no ongoing "Alex is at 8%" display
      for the group the way those apps show it continuously. Would need a
      `batteryLevel` field on `LocationPoint`/`startSharing` (same
      `battery_plus` plugin the warning above already uses) alongside the
      existing heading/speed, plus a place to surface it (roster row?
      marker badge?).
