# Group lifecycle — cleanup, expiry, and extension

Five moving pieces, all in `functions/src/index.ts`:

| Function | Trigger | What it does |
|---|---|---|
| `trackGroupActivity` | Firestore write on `groups/{id}/locations/{userId}` | Bumps the group's `lastActivityAt` timestamp |
| `endInactiveGroups` | Scheduled, every 30 min | Ends groups with no activity for 10h, **or** whose `tripExpiresAt` hard cap has passed |
| `warnExpiringGroups` | Scheduled, every 15 min | Flags groups nearing `tripExpiresAt` so the app can show an in-app warning banner |
| `cleanupEndedGroupData` | Firestore update on `groups/{id}` | The moment `status` flips to `'ended'`, deletes the `locations` subcollection |
| `purgeOldEndedGroups` | Scheduled, every 24h | Permanently deletes group docs 30 days after they ended |

Thresholds live in `functions/src/config.ts`.

## Trip lifetime, warnings, and extension

Every group gets a `tripExpiresAt` field, set to **24 hours from creation**.
This is a hard cap — the group ends when it's reached, regardless of
activity — so a convoy can never silently run forever.

To support multi-day trips (drive during the day, park overnight, resume
the next day), the owner can **extend the trip by another 24 hours** at
any time from the app's overflow menu (⋮ → "Extend trip 24h"). Extending
always sets the new deadline to *now + 24h*, not "old deadline + 24h" —
so it always gives a full fresh window rather than compounding leftover time.

**Warnings**, so the owner isn't caught out:
- **4 hours out** — an orange banner appears for everyone in the app:
  owners see an inline "Extend 24h" button; other members see the same
  heads-up and are told to ask the owner.
- **1 hour out** — the banner turns red/urgent if still unresolved.
- Both are dismissible per-session, but the banner reappears if the
  situation escalates (dismissing the 4h warning doesn't suppress the 1h one).
- Extending resets the warning state, so the *new* deadline gets its own
  4h/1h warnings later.

This directly covers the "stopped for the night" scenario: if a group
was created at, say, 9am and the convoy parks for the night at 8pm, the
owner will see the 4h warning around 5am the next morning (24h - 4h from
9am), well before the cap would hit — giving time to extend before
anyone needs to be moving again. If your trips reliably start later in
the day and you want the warning to land at a more sensible hour, tune
`EARLY_WARNING_LEAD_HOURS` in `config.ts`.

**Current limitation:** warnings are in-app only (no push notification),
so they only surface if the owner opens the app before the deadline. The
`warnExpiringGroups` function is written as the hook point for adding an
FCM push later — see the comment above it in `index.ts`.

## Why locations vs. metadata are treated differently

- **Locations die fast, group metadata dies slow.** The moment a trip
  ends, live position data is wiped immediately. Group metadata (name,
  who was in it) sticks around for 30 days for a possible "past trips"
  view later, then gets purged too.
- **Two ways to end a group, one cleanup path.** Whether the owner taps
  "End trip", the group goes quiet, or the hard cap is reached, all
  three just set `status: 'ended'` — `cleanupEndedGroupData` doesn't
  care which caused it.
- **Client-side backup.** `map_screen.dart` listens to the group doc
  directly and calls `stopSharing()` the instant it sees
  `status == 'ended'`, rather than waiting to get rejected by the
  security rule on the next write.

## Deploying

```bash
cd functions
npm install
cd ..
firebase deploy --only functions,firestore:rules,firestore:indexes
```

First deploy will prompt Firebase to build the composite indexes in
`firestore.indexes.json` — this can take a few minutes for existing data,
but is instant on an empty collection.

## Testing locally

```bash
firebase emulators:start --only functions,firestore
```

Scheduled functions (`endInactiveGroups`, `warnExpiringGroups`,
`purgeOldEndedGroups`) don't fire automatically in the emulator — trigger
them manually from the emulator UI's "Functions" tab, or lower the
thresholds in `config.ts` temporarily while testing.
