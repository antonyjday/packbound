# Changelog / dev log

Detailed, chronological build log for Packbound (formerly Convoy). Each entry
covers what changed, why, and (where relevant) how it was verified. This is
the working history for contributors — for a concise, user-facing feature
list see [README.md](README.md).

## Done

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
      That broke landscape though, where height is the scarce axis
      instead - a fixed vertical stack overflowed the shorter screen and
      overlapped the bottom route-info chips there. Made the rail
      orientation-aware (`railTop`/`railRight` helpers): vertical in
      portrait, back to the original horizontal row in landscape.
      Verified both orientations live via `adb emu rotate`.
- [x] Rebranded the app to "Packbound" (`packbound.net`). Updated all
      user-facing brand references (app title, sign-in headline, home
      app bar, share text, permission-explainer copy, the location-
      sharing foreground notification title) - left generic uses of the
      word "convoy" alone (a travel group, e.g. "Start a new convoy",
      "Remove from convoy?"), since those describe the feature, not the
      product name. Also closed the Android half of the applicationId
      TODO: registered a new Firebase Android app under
      `net.packbound.app` (`firebase apps:create`), replaced
      `google-services.json`, updated `firebase_options.dart`/
      `firebase.json`, renamed the Gradle `applicationId`/`namespace`,
      and moved `MainActivity.kt` to match the new package. The custom
      deep-link scheme is now `packbound://join/CODE` (was `convoy://`).
      Did NOT touch the Dart package name (`convoy_app` in
      `pubspec.yaml`) or iOS - see the TODOs below for why.
      Confirmed the old key's Android restriction was the blocker (black
      map, `Authorization failure` in logcat naming exactly
      `net.packbound.app` as missing from its allow-list); rather than
      edit that restriction, a new key (named "packbound.net") was
      issued and swapped in (`AndroidManifest.xml`,
      `DirectionsService`/`PlacesService`). While in there, also fixed a
      pre-existing bug: both services' `_androidCertSha1` constant
      (`EF3D285E...`) didn't match the actual debug keystore fingerprint
      at all (verified via `keytool -list`) - corrected to the real
      value. Verified live on two emulators: Maps tiles, route polyline,
      and turn-by-turn all render correctly under the new key.
- [x] Small map-screen polish pass, all reported/verified live on-device:
      added missing tooltips to the roster ("Group members") and refit
      ("Fit map to everyone") buttons - the "My location", step-route, and
      skip-route buttons already had them. Changed push-to-talk from
      press-and-hold to tap-to-start/tap-to-stop (`onTapDown`/`onTapUp`
      replaced with a single `onTap` toggling on `_recordingVoice`, dropping
      the now-unreachable `_cancelPushToTalk` gesture-cancel handler), with
      the tooltip text switching between "Tap to start recording a voice
      message" and "Tap to stop and send" to match - preferred over hold,
      per testing feedback that holding down was tricky. Reordered the
      owner's overflow menu so "End trip" sits directly above "Leave trip"
      (previously separated by the route/invite items and a divider).
- [x] Trimmed the turn-by-turn navigation bar's padding and icon size in
      landscape only (12px vertical padding/32px icon -> 6px/24px), leaving
      the instruction/distance text itself at full size - landscape has far
      less vertical slack than portrait (the top button rail runs
      horizontally there instead of down the side), and the bar sits
      in-flow above the map, pushing everything else down by its own
      height. Requested to free up room for the button rail without
      sacrificing how readable the directions are. Verified live in both
      orientations via `adb emu rotate`.
- [x] Added a per-trip type (Car/Train/Bicycle/Walk, see `lib/models/
      trip_type.dart`), picked via a `SegmentedButton` on the create-group
      screen and changeable afterward from the owner's "..." menu (a
      `SimpleDialog` picker, since `PopupMenuButton` can't nest submenus).
      Stored as a plain string field on the group doc (`tripType`, defaults
      to `car` for groups created before this existed), same isOwner()-gated
      update rule as the other owner settings - no rules change needed.
      Drives three things: (1) `SetRouteScreen`'s default "nearby" zoom
      level (`TripType.nearbyZoom` - car ~50mi, train ~100mi, bicycle ~12mi,
      walk ~3mi - a walking trip's plausible range is a driving trip's
      pointless close-up, and vice versa); (2) which quick-message presets
      show up (`lib/utils/quick_messages.dart` restructured from one flat
      list into per-type lists plus a shared "common" set - e.g. "Missed
      the train"/"On the train" only for train trips, "Need fuel" only for
      car); (3) `DirectionsService.route`'s Google Directions API `mode`
      parameter (`TripType.directionsMode`: driving/transit/bicycling/
      walking), so a route is now actually calculated for how the group is
      getting there, not just always driving directions with different
      UI/copy on top. Had to special-case transit: the Directions API
      flatly rejects the `waypoints` parameter combined with `mode=transit`
      (`INVALID_REQUEST`), so `DirectionsService.route` silently drops
      waypoints when the mode is transit, and the returned `RoutePlan`
      reflects that (not the originally-requested waypoints) so the map
      doesn't show stop markers a train route didn't actually route
      through; `SetRouteScreen` also warns the owner via SnackBar if they
      saved a train route with stops, since the drop would otherwise be
      silent. Found and fixed a real bug during testing: the quick-message
      bottom sheet was a fixed non-scrolling `Column` that happened to just
      barely fit car's 7 presets - train's 8 (4 type-specific + 4 shared)
      overflowed off the bottom of the screen. Fixed by capping the sheet
      at 80% of screen height and making its content scroll
      (`isScrollControlled: true` + `SingleChildScrollView`), which also
      makes it robust to any future preset-list length rather than
      re-breaking the next time a list grows. New tests in `trip_type_test.
      dart` and `quick_messages_test.dart`, plus additions to `group_test.
      dart`/`group_service_test.dart` (108 Dart tests total now). Verified live: home
      screen's 4-way segmented button (shortened "Bicycle" to "Bike" so all
      four fit on one line without wrapping), the menu picker, live preset
      switching, and `SetRouteScreen` opening at the correct wider zoom for
      a train trip. Did not live-test an actual saved transit/walking/
      cycling route against the real Directions API end-to-end (would need
      a real destination + location permission grant) - the mode plumbing
      and transit waypoint-dropping are verified by code review and the
      unit tests above, not a live route save.
- [x] Added a prominent "Set route" call-to-action on the map screen,
      shown only to the owner and only while no route exists yet (goes away
      the moment one is set) - "Set route" was otherwise just one line in
      the "..." menu, easy to miss when starting a new trip. Centered over
      the map (`Align(alignment: Alignment(0, 0.35))`), styled much bigger
      than the small circular FABs around it (brand coral, 18pt bold text,
      an icon) so it reads as the obvious next step rather than blending in.
- [x] Fixed a real bug reported live: changing trip type from the map's
      "..." menu and then opening "Set route" in the same session still
      requested driving directions regardless of the new type (e.g. a
      route just switched to Bike still came back as a car-shaped path) -
      confirmed the Directions API itself does return genuinely different
      routes per mode (a direct REST comparison of the same origin/
      destination returned 5.8km/24min for driving vs. 6.1km/22min for
      bicycling), so this was our bug, not an API/data limitation.
      Root cause: `SetRouteScreen` read `group.tripType` off the
      `ConvoyGroup` instance `MapScreen` was originally constructed with,
      but the menu's trip-type picker only ever updates `MapScreen`'s own
      live `_tripType` field (see the earlier trip-type entry above) - that
      `ConvoyGroup` object itself never gets recreated, so it kept whatever
      type was current when the map screen first opened. `SetRouteScreen`
      now takes an explicit `tripType` parameter instead of deriving it
      from `group.tripType`, and `MapScreen._openSetRoute` passes its live
      `_tripType` - same pattern already used for `initialRoute` (passed
      live from `_route`, not read off `group.route`). Verified live:
      created a Car trip, switched it to Bike via the menu, opened "Set
      route" (via the new CTA button above) and confirmed both the
      camera's default zoom and the saved route now genuinely reflect Bike
      rather than the stale Car value.
- [x] Test suite audit after the trip-type work above: added
      `test/services/directions_service_test.dart` covering the new
      `waypointsForMode` helper (extracted from `DirectionsService.route`
      specifically so the transit-drops-waypoints rule is unit-testable
      without a live network call - see the stale-tripType bug fix above,
      which was exactly this class of routing-logic bug) and
      `test/models/group_message_test.dart` (previously untested despite
      the push-to-talk feature adding `isVoice`/`audioUrl`/
      `audioDurationSeconds`). No existing tests were found stale/removed -
      the rest of the suite (member colors, navigation/route progress,
      polyline codec, invite links, location point status) is unrelated to
      recent UI/branding/trip-type work and still accurately reflects
      current behavior. 115 Dart tests total now.
- [x] Added a live clock and an arrival-time ETA to the map screen. The
      app bar shows the current time (just `DateTime.now()` at build
      time, refreshed for free off the existing 5s `_staleTicker` -
      no new timer needed), and the "You" progress chip now shows an
      actual clock-time arrival estimate (`DateTime.now().add(_myEtaDuration!)`)
      alongside the existing remaining distance/duration.
- [x] Fixed the "You" progress chip's ETA getting clipped in portrait
      on routes with stops, since `_RouteInfoChip` caps label width at
      300 logical px. Moved the remaining-stops count out of the "You"
      chip and onto the "Full route" chip instead, and dropped the
      redundant "to end" wording - verified live with a 2-stop, 44mi
      route that the full label (distance/duration/ETA) no longer
      truncates.
- [x] Swapped the app bar's owner flag and clock: the "★ Owner" badge
      now sits next to the trip name (title, where the clock used to
      be) and the clock moved to the actions row (where the badge used
      to be). Confirmed a long trip name still just ellipsizes without
      overlapping the badge, since the name `Text` stays wrapped in
      `Expanded`.
- [x] Removed the visible text labels from the create-trip screen's
      Car/Train/Bike/Walk `SegmentedButton`, keeping icon-only segments.
      The labels wrapped onto a second line at larger system font sizes
      or on low-resolution screens, breaking the segmented layout. Each
      icon keeps a `Tooltip` and `Icon.semanticLabel` set to the trip
      type's name so it's still available on long-press/hover and to
      screen readers.

- [x] Fixed a real bug reported live: turn-by-turn nav would sometimes say
      "Make a U-turn" while driving correctly. Root cause: every throttled
      live-ETA recalculation (`_recalculateMyEta`, every ~2min/300m) asks
      the Directions API for a brand-new route from the current raw
      lat/lng, with no heading - the legacy API has no such parameter.
      Google often snaps that origin to the nearest road node, so the
      route's first step (always maneuver-less - see
      `classifyTurnManeuver`'s doc comment) can be a tiny snap-to-road
      segment whose start->end bearing is close to meaningless, but was
      still being compared against the device's live GPS heading to
      guess left/right/U-turn. Added a `minReliableStepBearingMeters`
      (25m) guard - falls back to the API's own "Head north on X" wording
      below that - and raised `movingSpeedThresholdMps` from 1.0 to 2.5
      m/s, since GPS heading itself is noisiest right around walking
      pace. All 115 tests still pass; this specific fix couldn't be
      repro'd live (needs real GPS noise while driving), so verified by
      code review + existing `classifyTurnManeuver` test coverage only.
- [x] Follow-up to the above: a single car-calibrated
      `movingSpeedThresholdMps` (2.5 m/s) meant Walk trips - typical pace
      ~1.2-1.8 m/s - would almost never clear it, silently losing both
      the turn relabeling and camera auto-follow for the whole trip.
      Moved it onto `TripType` as `movingSpeedThresholdMps` (car/train:
      2.5 m/s, bicycle: 2.0 m/s, walk: 0.8 m/s) so each mode gets a floor
      suited to its own realistic speed range instead of one number
      starving the slower ones. 118 tests now (added 3 for the new
      per-mode getter).
- [x] Added a marketing website + privacy policy for packbound.net
      (`website/index.html`, `website/privacy.html`, plain HTML/CSS, no
      build step), using the actual brand assets (`branding/*.svg`,
      colors/fonts from `packbound-brand-guide.html` - coral swapped for
      the app's actual darkened `#E65156` rather than the guide's
      original `#FF5A5F`). Privacy content is grounded in the real
      cleanup behavior in `CLEANUP.md`/`functions/src/index.ts` (location
      wiped immediately on trip end, metadata purged after 30 days,
      anonymous auth with no email/phone, no analytics/ads SDK anywhere
      in `pubspec.yaml`) rather than generic marketing claims. Added a
      `hosting` block to `firebase.json` pointing at `website/`. Verified
      by rendering both pages headlessly (Edge `--headless --screenshot`)
      at desktop and narrow widths - caught and fixed two real bugs this
      way: the phone-mock's ETA text running into the name with no gap,
      and a latent CSS Grid "blowout" risk (nowrap content could force
      the hero wider than its container on very narrow screens - grid
      items default to `min-width:auto`) fixed with an explicit
      `min-width:0` on the hero's grid children.
- [x] Pre-open-source tidy-up pass, after renaming the GitHub repo from
      `convoy` to `packbound`. Found and fixed several real leftovers
      from the rebrand, not just cosmetic ones:
      - iOS `Info.plist` still had the *old* `convoy://` deep-link scheme
        registered while Android and all the Dart code
        (`invite_link.dart`, `deep_link_service.dart`) already use
        `packbound://` - harmless today since iOS isn't built yet, but
        would've silently broken invite links the moment it is. Also
        fixed `CFBundleDisplayName`/`CFBundleName` (still "Convoy
        App"/"convoy_app" - the actual name iOS would show under the
        app icon) and the three `NSLocation*UsageDescription` strings
        (the real permission-dialog text a user sees), which still said
        "Convoy" - genuine user-facing bugs waiting to ship, not just
        docs.
      - `tool/simulate_trip.mjs` (manual multi-device test script) still
        used the pre-rebrand Android package
        (`com.example.convoy.convoy_app` instead of `net.packbound.app`)
        and generated invite links with the old `convoy://` scheme -
        would have silently failed against the current app build.
      - `PLATFORM_SETUP.md`'s deep-link section documented the old
        scheme throughout and referenced an `Info-additions.plist` file
        that doesn't actually exist in the repo - updated to match
        current reality (`packbound://`, `website/`, `packbound.net`).
      - Swapped generic (non-brand) uses of the word "convoy" to "trip"
        in five real shipped UI strings that were inconsistent with the
        rest of the app's own established terminology ("Start a new
        trip", "End trip", etc.): the invite share text, the location-
        permission explainer, the trip-expiry banner, the "removed from
        trip" dialog, and the "remove from trip?" confirmation + its
        tooltip.
      - Removed a stale "no app icon" TODO below - that shipped a while
        ago (see the Packbound branding entry above).
      - Cosmetic-only, zero functional risk: `pubspec.yaml` and
        `functions/package.json` descriptions still said "convoy
        groups"/"Convoy cleanup functions".
      Deliberately did NOT touch the Dart package name itself
      (`convoy_app`), the `ConvoyGroup`/`ConvoyApp`/`ConvoyStatusList`
      class names, or the Firebase project ID (`convoy-app-ajd`, which
      can't be renamed anyway) - see the TODO below for why the former
      is a separate, bigger piece of work. All 118 tests still pass;
      analyzer clean (same 4 pre-existing info-level lints as baseline).
- [x] Added `AuthService.updateLastSeen()` and wired it into a dedicated
      `authStateChanges` subscription in `main.dart` (a separate
      `StreamSubscription` alongside the existing `StreamBuilder`, not
      inside its `builder` - that gets re-invoked on unrelated rebuilds
      like a theme toggle using its last-cached snapshot, which would've
      re-written `lastSeen` far more often than intended). Previously
      `lastSeen` was only ever set once, at first sign-in
      (`signInAnonymously`) - reopening the app on a later day never
      touched it, so it really meant "account created at," not "last
      active." Now it updates on every app open (cold start resuming a
      persisted session, or a fresh sign-in), giving an actual "active
      in the last N days" signal queryable straight from the existing
      `users` collection - not new tracking, just making a field that
      was already being collected for a real reason actually mean what
      its name says. Added a line to the privacy policy explicitly
      naming it. Verified live: app resumes straight to the signed-in
      home screen with no crash/hang (the new subscription's cold-start
      path). 120 tests now (2 new for `updateLastSeen`); analyzer clean.
- [x] Added a second, secondary button under the map screen's "Set
      route" CTA - amber background, white text, reads "Just track" -
      for groups on a familiar/well-known route who just want live
      positions, not turn-by-turn or ETA. Persisted as a new
      `routeSkipped` bool on the group doc (owner-only, same
      `isOwner()`-gated update rule as the other owner settings - no
      firestore.rules change needed), rather than local widget state,
      since a local-only dismissal would reappear every time the app
      restarts during the same 24h trip. Dismissing only hides the CTA
      banner - "Set route" stays reachable in the owner's "..." menu
      the whole time, and actually setting a route makes `routeSkipped`
      moot anyway since the banner's condition already requires
      `route == null`. Verified live: banner (both buttons) disappears
      immediately after tapping the new one, "Set route" still present
      in the menu afterward. Also chased down an ANR hit during manual
      testing (create trip -> Set route -> back -> back) - the main
      thread's stack showed it blocked entirely inside Android's own
      `LocationManager.removeNmeaListener` binder call, several layers
      below any app code; didn't reproduce on a careful retry, and
      nothing in this change touches location code at all - logged as
      emulator location-service flakiness, not an app bug. 124 tests
      now (4 new: `ConvoyGroup` toMap/fromDoc coverage +
      `GroupService.setRouteSkipped`); analyzer clean.
- [x] First pass of Play Store submission prep. Generated a real release
      keystore (`packbound-upload` alias) deliberately stored outside the
      repo entirely (`C:\Users\anton\android-keystores\` - defense in
      depth beyond `.gitignore`, now that the repo is public), wired into
      `build.gradle.kts` via `android/key.properties` (gitignored) with a
      fallback to debug signing when that file's absent, so a fresh
      checkout with no keystore still builds. Verified both
      `flutter build apk --release` and `flutter build appbundle
      --release` produce artifacts actually signed with the new cert
      (checked via `apksigner`/`jarsigner`, not just assumed). Also wrote
      `PLAY_STORE_SETUP.md` - store listing copy (short/full description),
      Data Safety questionnaire answers, and the background-location
      permissions declaration justification, all matching what the code
      and privacy policy actually say rather than generic boilerplate -
      plus a 1024x500 feature graphic built from the real brand assets
      and four real phone screenshots (home screen, live route/ETA, dark
      mode, quick messages) in `store-assets/`. Deliberately left for the
      user: adding the new keystore's SHA-1 to the Maps API key and
      Firebase's Android app config (Console-only steps), and the actual
      Play Console submission itself.
- [x] Release keystore's SHA-1/SHA-256 added to both the Maps API key's
      Android restriction and Firebase's Android app config (done directly
      in each Console by the user) - release-signed builds now actually
      work end-to-end, verified by installing a release build and manually
      testing Maps/routing.
- [x] Bumped `targetSdk` from a hardcoded `34` to `flutter.targetSdkVersion`
      (currently resolves to 36), matching how `compileSdk` already tracks
      the Flutter SDK rather than pinning to a value that'll eventually
      fall below Google Play's minimum target API requirement (which moves
      up annually). No manifest changes needed - `AndroidManifest.xml`
      already declares `foregroundServiceType="location"` and
      `POST_NOTIFICATIONS`, which is what the API 34+ jump actually
      requires. Verified: `flutter test` (124/124) and a manual pass on a
      freshly-booted emulator (cold start, notification permission,
      sign-in screen) with no edge-to-edge/inset regressions - the app has
      no custom `SystemChrome` calls, so it rides Flutter's Material
      defaults.
- [x] Voice messages no longer auto-play the instant the alert dialog
      appears (`map_screen.dart`, `_maybeShowNextMessageAlert`) - a clip
      starting to talk on its own was startling, especially with the
      volume up while driving. The clip now preloads silently in the
      background as soon as the dialog shows, and a play/pause button
      (`StreamBuilder<PlayerState>` over the `just_audio` player) lets the
      recipient start it whenever they're ready; replaying after it
      finishes seeks back to the start first. Multiple voice messages
      received before the first is played were already queued FIFO one
      dialog at a time (`_pendingMessageAlerts`) - that queue needed no
      changes, since it already gates on the dialog being dismissed, not on
      playback finishing. Also fixed: `just_audio`'s `playing` flag stays
      `true` after a clip runs to completion (it only reflects "not
      paused", not "still producing audio"), so the button folds in
      `processingState == completed` to correctly revert to a play icon
      once the clip actually finishes, ready to replay in case it was
      missed the first time. `flutter analyze`/`flutter test` clean
      (124/124); manually verified on the emulator end-to-end (play ->
      auto-revert on completion -> replay) using a real uploaded voice
      clip, not just the dialog's appearance.
- [x] Upgraded the Android invite link from the `packbound://join/CODE`
      custom scheme to a verified `https://packbound.net/join/CODE` App
      Link, so invites degrade gracefully (a real webpage with a download
      link and the code) for anyone who taps one without the app
      installed - `buildInviteLink()`/`extractInviteCode()` in
      `lib/utils/invite_link.dart` now build/parse the https form (the
      legacy custom scheme is still parsed too, so nothing that already
      has an old link breaks). Added a second `autoVerify="true"`
      intent-filter to `AndroidManifest.xml`, hosted
      `website/.well-known/assetlinks.json` (both the release and debug
      signing certs' SHA-256 fingerprints, so it verifies against a
      locally debug-built APK too, not just a release one), and a
      `website/join/index.html` fallback page (Firebase Hosting rewrite:
      `/join/**` -> that page) showing the invite code plus a download
      link. Had to explicitly un-ignore `.well-known/` in `firebase.json`
      - its default `**/.*` ignore rule would otherwise have silently
      excluded the verification file from every deploy. Verified for
      real, not just by reading the manifest: `adb shell pm get-app-links`
      shows `packbound.net: verified`, and firing the link with no
      package specified opens the app directly with no browser/chooser,
      both on a fresh cold-booted emulator and with the app already
      running - correctly pre-fills the invite code field for a bogus
      code, and correctly auto-joins the actual group for a real one.
      iOS still only has the custom scheme (needs Team ID/bundle ID from
      the still-pending Mac/Xcode setup first - see PLATFORM_SETUP.md).
- [x] Real-world testing turned up four issues, all fixed:
      1) the shared route never recalculated if the owner detoured from it;
      2) waypoints stayed on the shared route forever, even long after the
      owner had passed them; 3) the owner manually or physically skipping
      ahead only ever updated their own device's personal ETA overlay, never
      the group's shared route everyone else sees; 4) the OS gesture/nav bar
      overlapped the map's zoom controls and the bottom two info chips.
      Root cause of 1-3 together: the shared `route` (origin/waypoints/
      polyline/distance/duration on the group doc, rendered identically on
      every member's map) was write-once at set-route time - only each
      viewer's own separate, *personal* ETA overlay
      (`_recalculateMyEta`/`_myRoutePolyline`) ever recalculated live, and
      that was never written back anywhere shared. Fixed with a new
      owner-only `_maybeRerouteSharedRoute` (`map_screen.dart`), run
      alongside the existing personal recalculation on every location tick:
      requests a fresh route from Directions (origin = the owner's current
      position, destination unchanged, waypoints = whichever remain) and
      overwrites the shared route via the existing `GroupService.setRoute`
      whenever either (a) the owner has come within 100m of the next
      waypoint (new `remainingWaypoints` in `route_progress.dart` - waypoint
      dropped from the route for everyone, origin becomes wherever the
      owner currently is, "start point" included per the same logic) or (b)
      the owner has drifted more than 150m from the route's own polyline (new
      `distanceFromRouteMeters`), throttled to at most once every 2 minutes
      like the existing personal recalculation, so a long genuine detour
      doesn't hammer the Directions API on every ~3s location tick. For (4),
      added `MediaQuery.of(context).padding.bottom` to both the `GoogleMap`
      widget's `padding` (pushes the native zoom buttons up) and the bottom
      info chip stack's offset. 8 new unit tests for the two new
      `route_progress.dart` functions (134 total, all passing);
      `flutter analyze` clean. Verified live end-to-end on the emulator, not
      just by reading the code: geo-fixed the owner to a route's waypoint's
      exact coordinates and confirmed via direct Firestore inspection that
      `route.waypoints` emptied, `route.origin` became the owner's live
      position, and `distanceMeters`/`durationSeconds` dropped to match a
      genuinely shorter recalculated route - all under a fresh `setAt`,
      confirming a real Directions call and a real shared write, not a
      no-op. Also confirmed the zoom controls now sit with a clear gap
      above the OS nav bar rather than flush against it.
- [x] More real-world testing feedback: the turn-by-turn instruction
      banner was often slow to update once a maneuver was actually passed
      - the live marker position updated promptly, but the instruction
      text lagged behind, sometimes for a while. Root cause:
      `nextNavigationStep` (`navigation_progress.dart`) only ever counted a
      step as "reached" within a tight 40m radius of the API's exact
      endpoint coordinate - ordinary GPS drift plus normal lane position
      (rarely exactly on the routed centerline) regularly puts real
      driving further than that away, especially at wider junctions and
      roundabouts, leaving the banner stuck on an already-completed
      maneuver until happening to come within radius of a *later* step.
      Bumped `stepArrivalRadiusMeters` to 75m - still tighter than
      `waypointArrivalRadiusMeters`/`ownerWaypointClearRadiusMeters` in
      route_progress.dart since consecutive turns are legitimately closer
      together than planned stops, but forgiving enough for real-world
      positioning. New unit test covers a position ~60m off a step's exact
      endpoint (inside the new radius, outside the old one) still
      correctly advancing. 135 tests total, all passing; `flutter analyze`
      clean.
- [x] "Chase mode" - a per-member opt-in that ignores the owner's set
      route/waypoints entirely and instead personally navigates to
      wherever the owner currently is (or was last seen), continuously
      updating as the owner moves. Reuses the same throttled
      `DirectionsService.route()` pattern as the personal ETA overlay
      (`_recalculateMyEta`/`_maybeRecalculateMyEta` in `map_screen.dart`,
      extended to branch on the owner's live position instead of the
      route's destination/waypoints when Chase mode is on) - no new API
      call machinery needed. Two entry points funnel through the same
      `_toggleChaseMode`: a center-screen "Chase mode"/"Just track" button
      pair (same slot/style as the owner's "Set route"/"Just track") for a
      non-owner member before a route exists, and a checkbox in the "..."
      menu once one does, or once the center prompt's been dismissed
      either way (`_chaseCtaDismissed` - a one-way switch for this screen
      session, same idea as the owner's route CTA moving into the menu
      once a route exists). The "skip ahead" FAB hides while chasing
      (nothing left for it to mean), and the bottom info chips show
      "Chasing &lt;name&gt;" / "To them: X mi · ETA Y" instead of the usual
      "Full route"/"You" labels. Off by default; plain local `State` field,
      not synced anywhere - resets each time the screen is reopened, same
      as the existing manual "skip ahead" override.
      Verified live end-to-end on the emulator (not just by reading the
      code), joining as a plain member (not owner) of a throwaway test
      group: center button appears before a route exists and disappears
      after either button is pressed; enabling Chase mode produces a real
      Directions call and turn-by-turn instructions toward the owner's
      actual location; the menu toggle works identically once a route
      exists; "Just track" dismisses without enabling anything (confirmed
      clean after an earlier false alarm turned out to be a UI
      coordinate-shift artifact from an unrelated long delay between
      reading the button's position and tapping it, not a real bug).
- [x] Fixed: after the zoom controls started shifting up to clear the OS
      gesture/nav bar, they ended up colliding with the push-to-talk mic
      button instead, which was still pinned at a fixed `bottom: 130` with
      no inset. Mic button now shifts up by the same
      `MediaQuery.padding.bottom` amount so the two move in tandem.
- [x] Fixed: closed testing installs from the Play Store showed a blank
      map (`Authorization failure` in logcat) despite the Maps API key
      already having the debug and upload-key SHA-1s registered. Root
      cause: Play App Signing re-signs whatever gets uploaded, so the
      cert on a real Play-distributed install is neither the debug nor
      upload key - and in this case not even the "current" App signing
      key Play Console shows as "in use", but a previous/rotated one
      only visible under "Previous app signing keys" on the App signing
      page. Fixed by registering that cert's SHA-1 with both the Maps
      API key (Google Cloud Console) and Firebase - see
      PLAY_STORE_SETUP.md's "Play App Signing certificates" section for
      all four certs now registered and where to look if a future
      release regresses this again.
- [x] New scheduled Cloud Function `purgeStaleUserProfiles` - deletes
      `users/{uid}` profile docs (display name, lastSeen, push token)
      untouched for `USER_PROFILE_RETENTION_DAYS` (180 days). Found while
      writing packbound.net/delete-data for the Play Store Data Safety
      form: this doc lives outside any group's subcollections, so none of
      the existing group-expiry sweeps ever cleaned it up - a device that
      signed in once and never returned would have kept a profile
      forever. Gives the "data is deleted automatically" claim on that
      page (and in the privacy policy) a real backstop instead of relying
      purely on someone emailing in a deletion request.
- [x] Removed the clock from the map screen's app bar - redundant with
      the OS status bar's own clock, right next to it.

## Needed before this is usable end-to-end

- [ ] iOS Firebase config — `flutterfire configure` didn't produce a
      `GoogleService-Info.plist` (needs to be regenerated, ideally from a Mac
      with Xcode installed). iOS hasn't been built or run at all yet.
- [ ] iOS Google Maps API key — still a placeholder in `AppDelegate.swift`.

## Known gaps / follow-ups called out in the code

- [ ] iOS still has no universal link (`apple-app-site-association`) -
      blocked on the Mac/Xcode setup below for a real Team ID/bundle ID;
      Android's half of this is done (see "Done" above). See
      PLATFORM_SETUP.md for the exact remaining steps.
- [ ] iOS bundle ID is still the Flutter-generated placeholder
      (`com.example.convoy.convoyApp`) - rename to something under
      `packbound` once iOS is actually being configured (blocked on the
      Mac/Xcode step below anyway, so left as-is for now rather than
      guessing at a value with nothing to verify it against).
- [ ] The Dart package itself is still named `convoy_app`
      (`pubspec.yaml`'s `name:` field), which cascades into
      `import 'package:convoy_app/...'` across dozens of files in `lib/`
      and `test/`, plus the `ConvoyGroup` model class and
      `convoy_status_list.dart` widget file. All internal-only - zero
      effect on the shipped app or anyone using it - but a full rename to
      `packbound`/`PackboundGroup`/etc. would be a real mechanical
      refactor touching most of the codebase, not a quick fix. Deliberately
      not done in the same pass as the smaller rebrand cleanups (deep link
      scheme, `tool/simulate_trip.mjs`, doc references) - do this as its
      own separately-tested change, not bundled with anything else.

## Future feature ideas (not started)

- [ ] In-app group voice call — a button to join a live audio call with
      everyone currently on the trip. Push-to-talk (see "Done" above)
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
- [ ] Android Auto support - today Packbound declares no car-app support,
      so it's invisible to Auto and just keeps running normally on the
      phone in the background while Auto handles nav separately (no
      Play Store action needed for that - see PLAY_STORE_SETUP.md).
      Actually showing up on the head unit screen is a real feature, not
      a submission checkbox, and shouldn't be started until the existing
      phone-screen turn-by-turn nav (`lib/utils/navigation_progress.dart`,
      `lib/utils/route_progress.dart`, `set_route_screen.dart`/
      `map_screen.dart`) has real-world mileage - Auto's review bar and
      driver-distraction expectations are higher than a phone screen's,
      so bugs there are worse to ship. Rough path once that's proven out:
      - Prerequisite: apply for Car App Library category entitlement in
        Play Console before any Auto UI is even visible on a head unit -
        this is a manual Google approval step, separate from normal app
        review, and worth kicking off early given unknown lead time.
        Packbound most likely fits **Navigation** (shared route/ETA) or
        **Messaging** (quick messages/voice clips) - possibly both, but
        each category has its own template rules, so picking one to start
        is simpler than building against two at once.
      - Build a car-screen UI with `androidx.car.app` (Car App Library) -
        this is a hard requirement, not a nice-to-have: Auto restricts
        head-unit screens to library templates, so none of the existing
        Flutter map/UI code can be reused as-is for the car screen itself.
      - Scope the first version narrow - e.g. live ETA/next-turn plus
        roster status as a Navigation-template screen - rather than
        porting the full phone feature set (voice messages, QR join, etc)
        in one pass.
      - Re-test the driver-distraction/interaction rules specifically for
        whatever's shown on the car screen, since Google's Auto review
        checks this independently of the phone app.
