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
   only for convoy/group location sharing, and ideally the app should
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
  "Convoy is sharing your location" notification — that confirms the
  foreground service is alive and updates keep flowing.
- iOS: start sharing, lock the device or switch apps — you should see the
  blue "location in use" pill/bar at the top of the screen periodically.
- Both: verify Firestore `groups/{id}/locations/{uid}.updatedAt` keeps
  advancing while the app is backgrounded, not just in foreground.

## Invite deep links (`convoy://join/CODE`)

Both manifests are already wired up (Android intent-filter, iOS
`CFBundleURLTypes`) to open the app when someone taps a
`convoy://join/CODE` link — from the share sheet in `InviteScreen`, a
text message, etc. The `DeepLinkService` in `lib/services` picks it up
and `HomeScreen` auto-joins once the user is signed in.

One thing to fix before shipping: in `Info-additions.plist`, replace
`com.yourcompany.convoy` in `CFBundleURLName` with your actual bundle
identifier (matches whatever's in your Xcode project's Signing &
Capabilities tab).

**Limitation of a custom scheme (`convoy://`) vs. a universal/app link
(`https://yourdomain.com/join/CODE`):** a custom scheme only works if the
app is already installed — tapping it with the app not installed just
fails silently (iOS) or offers nothing useful (Android), and it won't
unfurl as a nice preview in a text message. A universal/app link degrades
gracefully to a normal webpage (e.g. "Get the app" + a way to still see
the invite) and looks like a real link everywhere. Upgrading requires:

- A real domain you control.
- Hosting `.well-known/apple-app-site-association` (iOS) and
  `.well-known/assetlinks.json` (Android) at that domain, referencing
  your app's Team ID/bundle ID and SHA-256 signing cert fingerprint.
- Adding the `applinks:yourdomain.com` associated domain (iOS,
  Signing & Capabilities) and an `autoVerify="true"` intent-filter with
  `android:host="yourdomain.com"` (Android manifest) alongside the
  existing custom-scheme one.

Not required to ship the current version — the custom scheme works fine
for "tap link in a message, app opens, code pre-filled" as long as
everyone in the group already has the app installed, which is the
realistic case for convoy members. Worth revisiting if you want the
invite link to also work as a soft app-install prompt for someone who
doesn't have Convoy yet.
