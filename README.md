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
- **Trip lifecycle** — groups get a 24h hard-cap expiry (extendable by the
  owner), auto-end after 10h of inactivity, and get an in-app 4h/1h warning
  banner as the deadline approaches. Ended groups have their live location
  data wiped immediately; group metadata is purged after 30 days.
- **Shared trip route** — the owner taps a destination and any planned stops
  right on the map; it's resolved into a real driving route (via the
  Directions API) and shown live to every member, along with the full-trip
  distance/ETA and each member's own live distance/ETA to the destination.
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
- [ ] Route search/autocomplete — setting a destination is currently
      tap-on-the-map only. Address search would need the Places API enabled
      (separate billing surface from Directions/Maps SDK) - deferred for now.
- [ ] Live "my ETA" always routes straight to the final destination, not the
      next unvisited waypoint - there's no tracking of which stops a member
      has already passed.
- [ ] Push notifications for trip-expiry warnings — currently in-app only, so
      the owner only sees them if they have the app open before the deadline
      (`warnExpiringGroups` in `functions/src/index.ts` is written as the
      hook point for adding FCM).
- [ ] Custom URL scheme (`convoy://`) only works if the app is already
      installed. Upgrading to a universal/app link
      (`https://yourdomain.com/join/CODE`) would let invites degrade
      gracefully for people who don't have the app yet — needs a real domain
      and hosting `.well-known/apple-app-site-association` /
      `assetlinks.json`. See PLATFORM_SETUP.md for details.
- [ ] No automated tests yet (`test/` is empty).
- [ ] `applicationId`/bundle ID are still the Flutter-generated
      `com.example.convoy.*` — rename before publishing to either app store.
- [ ] No app icon / launch screen customization — using Flutter defaults.
