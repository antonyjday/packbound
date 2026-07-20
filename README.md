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
  small toggle button if you want to pause it).
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
  lets you walk the camera (not your actual route) through each stop in
  order, then the destination, then
  your own current location, then back to the start.
- **Offline awareness** — banner when the device loses connectivity.

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
      `firebase_auth_mocks` + `mocktail` mocking) and `firestore.rules`
      itself (needs the emulator + `@firebase/rules-unit-testing`, a
      separate Node test suite - the only thing that would've caught the
      group-creation batch/rules bug from earlier) are follow-ups below.
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
- [ ] In landscape orientation, the bottom-left route info stack (marker
      legend, full-route chip, "you" chip) should lay out left-to-right
      instead of stacked top-to-bottom, since vertical space is scarcer.
- [ ] Route search/autocomplete — setting a destination is currently
      tap-on-the-map only. Address search would need the Places API enabled
      (separate billing surface from Directions/Maps SDK) - deferred for now.
- [ ] Custom URL scheme (`convoy://`) only works if the app is already
      installed. Upgrading to a universal/app link
      (`https://yourdomain.com/join/CODE`) would let invites degrade
      gracefully for people who don't have the app yet — needs a real domain
      and hosting `.well-known/apple-app-site-association` /
      `assetlinks.json`. See PLATFORM_SETUP.md for details.
- [ ] Service-layer tests (`GroupService`, `AuthService`) with mocked
      Firestore/Auth, and a separate Firestore-rules test suite against the
      emulator - see the "Done" note above.
- [ ] `applicationId`/bundle ID are still the Flutter-generated
      `com.example.convoy.*` — rename before publishing to either app store.
- [ ] No app icon / launch screen customization — using Flutter defaults.
