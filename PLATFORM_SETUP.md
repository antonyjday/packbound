# Platform setup checklist — Android & iOS

## Android (android/app/build.gradle)

Set these in the `android { defaultConfig { ... } }` block:

```
minSdkVersion 26      // geolocator background support wants 26+; 21 works but
                       // background location permission only exists from API 29,
                       // so devices below that will only get foreground updates
targetSdkVersion 34
```

Also add your Maps API key into `AndroidManifest.xml` (already scaffolded —
replace `YOUR_ANDROID_GOOGLE_MAPS_API_KEY`). Get one from the Google Cloud
Console with the "Maps SDK for Android" enabled.

The same key also needs the **Directions API** enabled (used by
`DirectionsService` to resolve the owner's planned route into an actual
driving path) - it's called via raw REST from the app, not the Maps SDK, so
requests include `X-Android-Package`/`X-Android-Cert` headers to have the
key's Android app restriction honored. The key string itself lives in
`lib/services/directions_service.dart` alongside those headers - update both
together if you rotate the key or change the app's signing cert.

Runtime permission flow to implement in the UI (the `ensurePermission()`
method in `location_service.dart` handles the requests, but Android forces
a specific UX):
1. Ask for fine location first ("while using the app").
2. Only after that's granted, ask for background location — Android shows
   this as a *separate* system dialog with wording like "Allow all the time",
   and on some OEM skins the user has to go into Settings manually. Consider
   showing your own explanation screen before the OS prompt (Google requires
   this for apps requesting background location on Play Store review).

## iOS (ios/Runner/Info.plist + Xcode)

1. Merge the keys from `Info-additions.plist` into your real `Info.plist`.
2. In Xcode: Target → Signing & Capabilities → "+ Capability" →
   **Background Modes** → check **Location updates**.
3. Add your Maps API key: in `ios/Runner/AppDelegate.swift`, call
   `GMSServices.provideAPIKey("YOUR_IOS_GOOGLE_MAPS_API_KEY")` before
   `GeneratedPluginRegistrant.register`.
4. Apple App Store review is strict about background location — your
   privacy policy and in-app explanation must clearly state it's used
   only for trip/group location sharing, and ideally the app should
   visibly indicate (e.g. a persistent banner) when sharing is active.
   `showBackgroundLocationIndicator: true` (already set) helps satisfy this.
5. Push notifications (trip-expiry warnings, `NotificationService`) are
   Android-only for now. To bring them to iOS once the rest of the iOS setup
   above is done: add the **Push Notifications** and **Background Modes →
   Remote notifications** capabilities in Xcode, then generate an APNs auth
   key (or certificate) in the Apple Developer portal and upload it under
   Project Settings → Cloud Messaging in the Firebase console.

## Testing background behavior

- Android: start sharing, press Home, watch for the persistent
  "Packbound is sharing your location" notification — that confirms the
  foreground service is alive and updates keep flowing.
- iOS: start sharing, lock the device or switch apps — you should see the
  blue "location in use" pill/bar at the top of the screen periodically.
- Both: verify Firestore `groups/{id}/locations/{uid}.updatedAt` keeps
  advancing while the app is backgrounded, not just in foreground.

## Invite deep links (`https://packbound.net/join/CODE`)

The shared invite link is now the `https://packbound.net/join/CODE`
universal/app link, built by `buildInviteLink()` in
`lib/utils/invite_link.dart` and used for both the share-sheet text and
the QR code in `InviteScreen`. The legacy `packbound://join/CODE` custom
scheme still exists in the Android manifest and is still parsed by
`extractInviteCode()` (and `tool/simulate_trip.mjs` still uses it for
scripted testing, since specifying the target package there bypasses
verification anyway) - nothing that already generated or hard-coded that
link needs to change.

**Android: done.** `android/app/src/main/AndroidManifest.xml` has a
second `autoVerify="true"` intent-filter for
`https://packbound.net/join/*`, verified against
`website/.well-known/assetlinks.json` (lists both the release and debug
signing certs' SHA-256 fingerprints, so verification works on both a
real installed build and a locally debug-built one). `firebase.json`
explicitly un-ignores `.well-known/` (the hosting config's default
`**/.*` ignore rule would otherwise silently exclude it) and rewrites
`/join/**` to `website/join/index.html`, a fallback page that shows the
invite code and a download link for anyone who taps the link without
the app installed, or before Android's verification has completed.

**iOS: still not done** - blocked on the same Mac/Xcode setup as the
rest of iOS (see above). Needs, once that's underway:
- Hosting `.well-known/apple-app-site-association` at packbound.net,
  referencing the real Team ID + bundle ID (placeholder
  `com.example.convoy.convoyApp` right now - see the iOS bundle ID gap
  in CHANGELOG.md).
- Adding the `applinks:packbound.net` associated domain in Xcode's
  Signing & Capabilities.
- `Info.plist`'s `CFBundleURLName` still needs updating to match
  whatever real bundle ID iOS ends up with, same as already noted here
  before this section was updated.

Until then, iOS keeps using the `packbound://` custom scheme only
(works fine as long as the recipient already has the app installed,
same limitation as Android had before this change).
