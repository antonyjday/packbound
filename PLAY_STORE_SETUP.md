# Google Play Store submission notes

Reference material for the actual Play Console submission - this repo can't
fill out Play Console's forms directly, so this is copy-paste-ready content
plus a record of what's already been done, kept here rather than only in
chat history.

## Release signing - done

A real release keystore now exists (not the debug one release builds used
before):

- Location: `C:\Users\anton\android-keystores\packbound-release.jks`
  (deliberately outside this repo, not just gitignored - defense in depth
  now that the repo is public)
- Alias: `packbound-upload`
- Config: `android/key.properties` (gitignored; `build.gradle.kts` falls
  back to debug signing if this file is absent, so a fresh checkout with no
  keystore still builds)
- Fingerprints:
  - SHA-1: `E9:B6:E5:39:ED:38:CE:DA:37:E2:88:B7:D6:EB:C8:BE:C9:64:90:60`
  - SHA-256: `2E:F3:AC:89:CF:5B:B6:E1:7A:98:A6:6C:C0:D9:71:56:FC:61:F4:85:09:F4:C6:38:96:3B:EB:1F:B4:8F:90:D2`

**Action needed before a release-signed build actually works** (not
something doable from here - needs your Console logins):
- Add the SHA-1 above to the Google Maps API key's Android app restriction
  in Google Cloud Console (alongside the existing debug SHA-1 - keep both
  for now, since debug builds are still useful for testing). Without this,
  a release-signed build will show a black map / `Authorization failure`,
  same failure mode already seen once before with the debug key.
- Add the same SHA-1 (and SHA-256) to the Android app's config in Firebase
  Console (Project settings -> your Android app -> SHA certificate
  fingerprints). Not strictly required for anonymous auth itself, but
  Play Integrity / App Check / Dynamic Links all key off this list if you
  ever turn those on.
- **Back up `packbound-release.jks` and the password somewhere durable**
  (password manager + at least one other secure location). Losing it means
  losing the ability to publish updates under Google Play App Signing's
  upload-key model without going through Google's account-recovery process.

### Play App Signing certificates - all four registered (2026-08-01)

The SHA-1 above (`E9:B6:E5:39:...`) is the **upload key** - what
`packbound-release.jks` actually signs locally. It is *not* what ships to
users once Play App Signing is enrolled (the default for any app's first
Play Console upload): Google re-signs the distributed APK with its own
key, so the certificate a real device sees is different from the one a
locally-built `.apk`/`.aab` is signed with. This caused a real incident -
closed testing installs showed a blank map (`Authorization failure` in
logcat) even though the Maps API key already had the debug and upload
SHA-1s registered, because neither of those is the cert Play actually
used to sign what testers installed.

Play Console -> Protected with Play -> App signing lists the relevant
certs. All of the following SHA-1s need to be on **both** the Maps API
key's Android restriction (Google Cloud Console) **and** Firebase's SHA
certificate fingerprints list (Project settings -> your Android app) -
missing any one of them reproduces the same blank-map bug for whichever
build path uses that cert:

| Key | SHA-1 | Used by |
|---|---|---|
| Debug | `CD:1A:C7:7C:A...` (see Console for full value) | Local `flutter run` debug builds |
| Upload key | `E9:B6:E5:39:ED:38:CE:DA:37:E2:88:B7:D6:EB:C8:BE:C9:64:90:60` | `packbound-release.jks` - locally-built release `.apk`/`.aab` before Play re-signs it |
| App signing key (Classical) | `BB:8A:87:FC:8E:9A:E6:B4:F1:47:D9:0B:9B:05:F8:ED:85:FB:D4:CF` | Play's current signing key, "Classical key" block |
| App signing key (previous/rotated) | `A1:2D:60:A4:C2:52:D3:2D:72:E2:4B:BD:39:4F:D0:4A:77:1F:96:9F` | What the closed testing track actually shipped as of 2026-08-01 - found under "Previous app signing keys" on the App signing page, not the current "in use" key |

Note the **Post-quantum cryptography key** block on that same page
(`A3:D0:F3:2F:51:32:D3:86:D5:EE:63:E6:BC:ED:99:C1:18:3B:3C:1D` as of
2026-08-01) was a red herring here - it didn't match the failing cert,
and doesn't currently need registering. If a *future* release still
shows a blank map after checking the four certs above, check the App
signing page again for a new "Previous app signing keys" entry or a
key rotation - Play can change which cert actually signs a rollout
without much visibility into it from this repo.

Both artifacts build and are correctly signed with the new cert (verified
via `apksigner`/`jarsigner`):
- `flutter build apk --release` -> `build/app/outputs/flutter-apk/app-release.apk`
- `flutter build appbundle --release` -> `build/app/outputs/bundle/release/app-release.aab`
  (66.3MB - Play Store requires the `.aab` for new app submissions, not the `.apk`)

## Store listing copy

**App name:** Packbound

**Category:** Maps & Navigation (Travel & Local is a reasonable alternative)

**Short description** (80 char limit, exactly 80 below):

```
Live location sharing for travel groups - no account, no ads, no lingering data.
```

**Full description** (4000 char limit, ~1800 used):

```
Packbound keeps your travel group together with live location sharing, a
shared route, and turn-by-turn navigation - built around one trip at a
time, not permanent tracking.

FEATURES
- No account needed - sign in with just a display name, no email or phone
  number required
- Create or join a trip by invite code, QR code, or link
- See everyone's live position, heading, and speed on one map, with a
  clear signal status per person
- Background location sharing with a one-tap pause
- Trip type aware - Car, Train, Bicycle, or Walk - tunes routing, map
  zoom, and quick messages to how you're actually travelling
- The trip owner can set a shared route with stops; everyone gets their
  own live ETA and turn-by-turn directions - or skip the route entirely
  and just track each other on a route you already know
- Chase mode - fell behind? Get live directions straight to wherever the
  trip owner currently is, instead of following the planned stops
- Quick preset messages and voice clips to the group, plus low battery
  and lost-signal alerts
- Dark mode

PRIVACY, BUILT IN
Packbound is built to know as little about you as possible:
- No email, phone number, or password - ever
- Your location is only ever visible to the other members of your
  specific trip
- Location history is deleted the moment a trip ends - not eventually,
  immediately
- Trip details are purged automatically after 30 days
- No ads, no analytics, no tracking SDKs, nothing sold to third parties
- Source code is public - read exactly how your data is handled at
  packbound.net

Trips can't run forever, either - every trip automatically expires after
24 hours (extendable) or after 10 hours of inactivity, so there's never a
stale, forgotten trip quietly tracking anyone.

Learn more, or read the full privacy policy, at packbound.net.
```

**Contact email:** support@packbound.net

**Privacy Policy URL:** https://packbound.net/privacy

**Delete data URL:** https://packbound.net/delete-data

## Data Safety questionnaire

Answers below match what's actually in the code and the privacy policy -
keep them in sync if either changes.

**Data collected:**

| Type | Collected? | Shared with 3rd parties? | Purpose | Required? |
|---|---|---|---|---|
| Approximate/precise location | Yes (precise) | No - only processed by Firebase/Google Maps as service providers | App functionality | Yes, for the app's core feature (can be paused per-trip) |
| Name (display name, user-chosen) | Yes | No | App functionality | Yes |
| Audio (voice messages) | Yes, if sent | No | App functionality | No - optional feature |
| Messages (quick-message text) | Yes, if sent | No | App functionality | No - optional feature |
| Device or other IDs (push token) | Yes | No | App functionality (notifications) | No - notifications are supplementary |

**Not collected:** email address, phone number, precise/exact address,
race/ethnicity, political/religious beliefs, sexual orientation, health
info, financial info, photos/videos, contacts, calendar, browsing history,
search history, installed apps list, or any analytics/advertising
identifiers.

**Other questionnaire answers:**
- Is all user data encrypted in transit? **Yes** (Firestore/Firebase over TLS)
- Does the app provide a way to request data deletion? **Yes** - leaving a
  trip immediately stops that device sharing further location; there's no
  persistent account to delete separately since sign-in is anonymous with
  no recovery details (explain this in the account-deletion section rather
  than linking to an in-app deletion flow, since there's no traditional
  account to delete)
- Committed to Play Families Policy / directed at children? **No**
- Independent security review? No (small indie project - answer "No" rather
  than leave blank)

## Background location permission declaration

Play Console's Permissions Declaration Form (required because the app
requests `ACCESS_BACKGROUND_LOCATION` / `FOREGROUND_SERVICE_LOCATION`)
asks for a written justification. Draft:

```
Packbound is a live location-sharing app for travel groups (road trips,
group hikes, family outings, etc). The core feature is showing each
group member's real-time position on a shared map so the group can find
each other, regroup, or follow a planned route together.

Background location access is required because group members frequently
minimize the app while still travelling as part of the trip - to check
messages, use another navigation app, or answer a call. If location
sharing stopped the moment the app was backgrounded, the core feature
would fail exactly when it matters most, e.g. a passenger's position
disappearing from the map the instant they switch apps at a rest stop.

Users are clearly informed before granting this permission: a dedicated
in-app screen shown before the system permission prompt explains that
background access lets the group see their position while the app is
minimized, and a persistent notification is shown for the entire
duration background sharing is active, so it's never silently running.
Users can pause location sharing at any time with a single tap without
leaving the trip, and sharing (and the underlying location data) stops
entirely and is deleted the moment they leave the trip or the trip ends.
```

## Visual assets

- Feature graphic (1024x500): `store-assets/feature-graphic.png`
- Phone screenshots: `store-assets/screenshot-*.png`

(See `store-assets/` in the repo root - not shipped as app assets, just
staged here for uploading to Play Console.)

## Rollout process (not a content/code task, just a reminder)

**Closed testing is live** - the app is released to the closed testing
track at `https://play.google.com/apps/testing/net.packbound.app`
(website's "Join the beta" / "Join the Android beta" links across
`index.html`, `privacy.html`, `delete-data.html`, and `join/index.html`
all point here now, replacing the old direct-APK-from-GitHub links).

New developer accounts need a closed testing track with a minimum number
of opted-in testers (Google's exact current number/duration should be
checked directly in Play Console when you get there - it's changed over
time) before production access unlocks. Plan for that lead time separately
from everything else in this doc.
