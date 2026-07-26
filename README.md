# Packbound

Real-time location sharing for travel groups. Create a trip, invite people by
code, QR, or a `https://packbound.net/join/CODE` link (opens the app directly
if installed, otherwise a normal webpage), and see everyone's live position on
a shared map for the duration of the trip.

Marketing site + privacy policy for packbound.net live in
[website/](website/) — see that folder for deploying it.

## Features

- **No account needed** — sign in with just a display name.
- **Create or join a trip** — by 6-character invite code, QR code, or deep link.
- **Live map** — everyone's position, heading, and speed, with a signal
  status (live / weak / lost) per member.
- **Background sharing** — keeps reporting your position while the app is
  minimized, with a one-tap toggle to pause it.
- **Trip type** — Car, Train, Bicycle, or Walk, set when creating the trip
  (changeable later by the owner). Tunes the route-planning map's default
  zoom, which quick-message presets are offered, and the actual travel mode
  used to calculate routes/ETAs.
- **Shared route & turn-by-turn navigation** — the trip owner sets a start
  point, destination, and any stops; every member gets their own live ETA
  (distance, duration, and estimated arrival time), route line, and
  turn-by-turn directions to get there. The shared route itself keeps up
  with the owner too — waypoints clear as they're reached, and it
  recalculates if they detour. Route optional — a group on a familiar
  route can skip straight to just tracking each other's live position
  instead.
- **Chase mode** — any member can opt out of the set route and instead
  navigate straight to wherever the trip owner currently is (or was last
  seen), for catching up directly rather than following the planned stops.
- **Trip lifecycle** — trips auto-expire after 24h (owner can extend) or
  after 10h of inactivity, with warnings as the deadline approaches. Anyone
  can leave at any time; ownership passes automatically if the owner leaves
  or the trip is ever abandoned and later rejoined.
- **Quick messages & push-to-talk** — one-tap preset messages (relevant to
  the trip type, e.g. "Need fuel" for a drive, "Missed the train" for a
  train trip) or a tap-to-record voice clip, delivered to the group as an
  alert plus a push notification.
- **Low battery & lost-signal alerts** — the group is notified if your
  battery gets critically low, or if your signal goes quiet or you arrive.
- **Dark mode.**

## Tech stack

- **Flutter** (Android + iOS)
- **Firebase**: Auth, Firestore, Cloud Functions, Cloud Messaging, Storage
- **Google Maps**: Maps SDK, Directions API, Places API

## Getting started

1. `flutter pub get`
2. This app is linked to the `convoy-app-ajd` Firebase project
   (`lib/firebase_options.dart`, `android/app/google-services.json`). To
   point it at a different project, run `flutterfire configure`.
3. `flutter run` (Android emulator/device — see `flutter emulators` if you
   don't have one set up).

For Android/iOS-specific setup (Maps API keys, background location
entitlements, deep link wiring), see [PLATFORM_SETUP.md](PLATFORM_SETUP.md).
For how the trip expiry/cleanup Cloud Functions work and how to deploy them,
see [CLEANUP.md](CLEANUP.md).
For the detailed development history and current known gaps/TODOs, see
[CHANGELOG.md](CHANGELOG.md).

## Project structure

```
lib/
  models/       ConvoyGroup, LocationPoint
  screens/      sign-in, home, map, invite, QR scan, permission explainer
  services/     auth, group, location, deep-link
functions/      Cloud Functions — group expiry/cleanup (see CLEANUP.md)
firestore-tests/ firestore.rules test suite (Node, against the real emulator)
```
