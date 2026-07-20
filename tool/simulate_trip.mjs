#!/usr/bin/env node
// Manual multi-participant test: creates a Convoy trip with 3 members
// converging on a shared destination at a constant speed, and drives 2 real
// emulators through it so you can watch the live map. See tool/README.md.
//
// Usage: node tool/simulate_trip.mjs
// Requires: an Android emulator already running and visible (default
// serial below), a 2nd AVD available to launch headless, and the app's
// debug APK already built at build/app/outputs/flutter-apk/app-debug.apk.

import { execFileSync, spawn } from 'node:child_process';

// ---- Scenario config ----------------------------------------------------
const DESTINATION = { lat: 51.9022, lng: -2.0722 }; // Cheltenham town centre
const START_BEARING_DEG = 0; // due north of the destination
const START_DISTANCE_MILES = 5;
// Each traveler's own start point, as an offset (miles, bearing) from the
// nominal start point above - all within 1 mile of it.
const TRAVELER_OFFSETS = [
  { miles: 0, bearing: 0 }, // T0 (ghost/owner-setup) - starts exactly on it
  { miles: 0.4, bearing: 90 }, // T1 (visible emulator)
  { miles: 0.45, bearing: 220 }, // T2 (headless emulator)
];
const SPEED_MPH = 20;
const TICK_SECONDS = 5;
const SAFETY_CAP_MINUTES = 20;

const PROJECT_ID = 'convoy-app-ajd';
const WEB_API_KEY = 'AIzaSyCdXpPmF_phYAvM0m2EQqwmVTCG-GWMCPA'; // android client key, from lib/firebase_options.dart
const PACKAGE = 'com.example.convoy.convoy_app';
const APK_PATH = 'build/app/outputs/flutter-apk/app-debug.apk';

const VISIBLE_SERIAL = process.env.CONVOY_VISIBLE_SERIAL || 'emulator-5554';
const HEADLESS_AVD = process.env.CONVOY_HEADLESS_AVD || 'convoy_test_2';

// ---- Geo helpers ----------------------------------------------------------
const MILES_TO_KM = 1.60934;
const EARTH_RADIUS_KM = 6371.0088;
const toRad = (d) => (d * Math.PI) / 180;
const toDeg = (r) => (r * 180) / Math.PI;

function destinationPoint(lat, lng, bearingDeg, distanceKm) {
  const angDist = distanceKm / EARTH_RADIUS_KM;
  const bearing = toRad(bearingDeg);
  const lat1 = toRad(lat);
  const lng1 = toRad(lng);
  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(angDist) + Math.cos(lat1) * Math.sin(angDist) * Math.cos(bearing),
  );
  const lng2 =
    lng1 +
    Math.atan2(
      Math.sin(bearing) * Math.sin(angDist) * Math.cos(lat1),
      Math.cos(angDist) - Math.sin(lat1) * Math.sin(lat2),
    );
  return { lat: toDeg(lat2), lng: toDeg(lng2) };
}

function distanceKm(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

function bearingDeg(a, b) {
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function lerpPoint(a, b, fraction) {
  // Straight-line interpolation - fine at this scale (a few miles), and
  // matches how the app's own live ETA math (remainingLegs) already treats
  // distance: straight-line via Geolocator.distanceBetween, not road-network.
  return { lat: a.lat + (b.lat - a.lat) * fraction, lng: a.lng + (b.lng - a.lng) * fraction };
}

// ---- Google encoded polyline (precision 1e5), matching lib/utils/polyline_codec.dart ----
function encodePolyline(points) {
  let output = '';
  let prevLat = 0;
  let prevLng = 0;
  for (const { lat, lng } of points) {
    const latE5 = Math.round(lat * 1e5);
    const lngE5 = Math.round(lng * 1e5);
    output += encodeSignedNumber(latE5 - prevLat);
    output += encodeSignedNumber(lngE5 - prevLng);
    prevLat = latE5;
    prevLng = lngE5;
  }
  return output;
}
function encodeSignedNumber(num) {
  let sgnNum = num << 1;
  if (num < 0) sgnNum = ~sgnNum;
  return encodeNumber(sgnNum);
}
function encodeNumber(num) {
  let output = '';
  while (num >= 0x20) {
    output += String.fromCharCode((0x20 | (num & 0x1f)) + 63);
    num >>= 5;
  }
  output += String.fromCharCode(num + 63);
  return output;
}

// ---- Firestore REST value encoding -----------------------------------------
function fsValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(fsValue) } };
  if (typeof v === 'object') return { mapValue: { fields: fsFields(v) } };
  throw new Error(`Unsupported value: ${v}`);
}
function fsFields(obj) {
  const fields = {};
  for (const [k, val] of Object.entries(obj)) fields[k] = fsValue(val);
  return fields;
}

async function fsRequest(method, path, { token, body, query } = {}) {
  const qs = query ? `?${query}` : '';
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}${qs}`;
  const res = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`Firestore ${method} ${path} failed: ${res.status} ${JSON.stringify(json)}`);
  }
  return json;
}

async function signInAnonymously() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_API_KEY}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`Anonymous sign-in failed: ${JSON.stringify(json)}`);
  return { uid: json.localId, token: json.idToken };
}

function docIdFromName(name) {
  return name.split('/').pop();
}

function randomInviteCode(length = 6) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < length; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

// ---- adb / emulator helpers -----------------------------------------------
function adb(serial, ...args) {
  return execFileSync('adb', ['-s', serial, ...args], { encoding: 'utf8' });
}
function sh(cmd, args) {
  return execFileSync(cmd, args, { encoding: 'utf8' });
}
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function listSerials() {
  const out = sh('adb', ['devices']);
  return out
    .split('\n')
    .slice(1)
    .map((l) => l.trim().split(/\s+/)[0])
    .filter((s) => s && s.startsWith('emulator-'));
}

async function launchHeadlessEmulator(avdName) {
  const before = new Set(listSerials());
  const emulatorBin = `${process.env.ANDROID_HOME}\\emulator\\emulator.exe`;
  const child = spawn(emulatorBin, ['-avd', avdName, '-no-window', '-no-audio', '-no-boot-anim'], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();

  let serial = null;
  for (let i = 0; i < 60 && !serial; i++) {
    await sleep(2000);
    const now = listSerials().filter((s) => !before.has(s));
    if (now.length > 0) serial = now[0];
  }
  if (!serial) throw new Error(`Timed out waiting for ${avdName} to appear in adb devices`);

  console.log(`  ${avdName} -> ${serial}, waiting for boot...`);
  execFileSync('adb', ['-s', serial, 'wait-for-device']);
  for (let i = 0; i < 60; i++) {
    try {
      const booted = adb(serial, 'shell', 'getprop', 'sys.boot_completed').trim();
      if (booted === '1') break;
    } catch (_) {}
    await sleep(2000);
  }
  return serial;
}

async function joinAndDiscoverMember(serial, groupId, inviteCode, knownUids, pollToken) {
  adb(
    serial,
    'shell',
    'am',
    'start',
    '-a',
    'android.intent.action.VIEW',
    '-d',
    `convoy://join/${inviteCode}`,
    PACKAGE,
  );
  for (let i = 0; i < 20; i++) {
    await sleep(1500);
    const res = await fsRequest('GET', `groups/${groupId}/members`, { token: pollToken });
    const ids = (res.documents || []).map((d) => docIdFromName(d.name));
    const fresh = ids.filter((id) => !knownUids.has(id));
    if (fresh.length > 0) return fresh[0];
  }
  throw new Error(`Timed out waiting for ${serial} to join group ${groupId}`);
}

// Finds the sharing FAB via the accessibility tree (its Flutter `tooltip`
// shows up as content-desc) rather than a fixed pixel guess - a blind
// coordinate tap turned out to be unreliable in practice: it can land
// before the map screen has finished settling, or on a stray system
// dialog, with no way to tell the tap didn't do anything. This also lets
// us confirm (and report) the actual before/after state instead of
// assuming the tap worked.
async function dumpFabState(serial) {
  adb(serial, 'shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml');
  const xml = adb(serial, 'shell', 'cat', '/sdcard/window_dump.xml');
  const m = xml.match(
    /content-desc="(Start sharing my location|Stop sharing my location)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/,
  );
  if (!m) return null;
  const [, label, x1, y1, x2, y2] = m;
  return { sharing: label === 'Stop sharing my location', cx: Math.round((Number(x1) + Number(x2)) / 2), cy: Math.round((Number(y1) + Number(y2)) / 2) };
}

async function ensureSharingStarted(serial, label) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const state = await dumpFabState(serial);
    if (!state) {
      await sleep(2000);
      continue;
    }
    if (state.sharing) {
      console.log(`  ${label}: sharing already on`);
      return;
    }
    adb(serial, 'shell', 'input', 'tap', String(state.cx), String(state.cy));
    await sleep(2000);
    const after = await dumpFabState(serial);
    if (after?.sharing) {
      console.log(`  ${label}: sharing started`);
      return;
    }
  }
  throw new Error(`Could not confirm sharing started on ${serial} (${label})`);
}

// ---- Main -------------------------------------------------------------------
async function main() {
  console.log('Computing route geometry...');
  const nominalStart = destinationPoint(
    DESTINATION.lat,
    DESTINATION.lng,
    START_BEARING_DEG,
    START_DISTANCE_MILES * MILES_TO_KM,
  );
  const starts = TRAVELER_OFFSETS.map((o) =>
    o.miles === 0
      ? nominalStart
      : destinationPoint(nominalStart.lat, nominalStart.lng, o.bearing, o.miles * MILES_TO_KM),
  );
  const totalDistanceKm = starts.map((s) => distanceKm(s, DESTINATION));
  console.log(
    `  destination: ${DESTINATION.lat.toFixed(5)},${DESTINATION.lng.toFixed(5)} (Cheltenham centre)`,
  );
  starts.forEach((s, i) =>
    console.log(`  T${i} start: ${s.lat.toFixed(5)},${s.lng.toFixed(5)} (${(totalDistanceKm[i] / MILES_TO_KM).toFixed(2)} mi to go)`),
  );

  console.log('\nCreating 3 test identities...');
  const [t0, t1Ghost, t2Ghost] = await Promise.all([signInAnonymously(), signInAnonymously(), signInAnonymously()]);
  void t1Ghost;
  void t2Ghost; // only used as placeholders to keep naming symmetric; real T1/T2 identities come from the emulators joining below

  console.log('Creating group + route as T0 (temporary owner)...');
  const inviteCode = randomInviteCode();
  const now = new Date();
  const groupCreate = await fsRequest('POST', 'groups', {
    token: t0.token,
    body: {
      fields: fsFields({
        name: `Cheltenham sim ${now.toISOString().slice(0, 16)}`,
        createdBy: t0.uid,
        ownerId: t0.uid,
        inviteCode,
        inviteExpiresAt: new Date(now.getTime() + 24 * 3600 * 1000),
        status: 'active',
        tripExpiresAt: new Date(now.getTime() + 4 * 3600 * 1000),
        expiryWarningLevel: 0,
        membersCanInvite: true,
        createdAt: now,
        lastActivityAt: now,
      }),
    },
  });
  const groupId = docIdFromName(groupCreate.name);
  console.log(`  group ${groupId}, invite code ${inviteCode}`);

  await fsRequest('PATCH', `groups/${groupId}/members/${t0.uid}`, {
    token: t0.token,
    body: { fields: fsFields({ joinedAt: now, role: 'owner', sharingEnabled: true }) },
  });

  const routeDistanceMeters = Math.round(totalDistanceKm[0] * 1000);
  const routeDurationSeconds = Math.round((totalDistanceKm[0] / MILES_TO_KM / SPEED_MPH) * 3600);
  await fsRequest('PATCH', `groups/${groupId}`, {
    token: t0.token,
    query: 'updateMask.fieldPaths=route',
    body: {
      fields: fsFields({
        route: {
          origin: starts[0],
          destination: DESTINATION,
          waypoints: [],
          polyline: encodePolyline([starts[0], DESTINATION]),
          distanceMeters: routeDistanceMeters,
          durationSeconds: routeDurationSeconds,
          setAt: now,
        },
      }),
    },
  });
  console.log(`  route set (${(routeDistanceMeters / 1609.34).toFixed(2)} mi, ~${Math.round(routeDurationSeconds / 60)} min)`);

  console.log('\nJoining the visible emulator via deep link...');
  const t1Uid = await joinAndDiscoverMember(VISIBLE_SERIAL, groupId, inviteCode, new Set([t0.uid]), t0.token);
  console.log(`  T1 uid ${t1Uid} joined on ${VISIBLE_SERIAL}`);

  console.log('Launching headless emulator for the 3rd traveler...');
  const headlessSerial = await launchHeadlessEmulator(HEADLESS_AVD);
  console.log(`  installing app on ${headlessSerial}...`);
  adb(headlessSerial, 'install', '-r', APK_PATH);
  // Pre-grant BEFORE first launch - otherwise the first-run system dialogs
  // (location, and Android 13+'s POST_NOTIFICATIONS prompt from
  // NotificationService.init()) block the deep link intent, since it's
  // delivered to an activity that's covered by a system dialog rather than
  // one that's actually reached HomeScreen yet.
  adb(headlessSerial, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_FINE_LOCATION');
  adb(headlessSerial, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_COARSE_LOCATION');
  try {
    adb(headlessSerial, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_BACKGROUND_LOCATION');
  } catch (_) {} // some API levels reject granting this before fine/coarse are committed - harmless
  try {
    adb(headlessSerial, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS');
  } catch (_) {} // no-op below API 33
  adb(headlessSerial, 'shell', 'am', 'start', '-n', `${PACKAGE}/.MainActivity`);
  await sleep(6000);
  console.log('  joining via deep link...');
  const t2Uid = await joinAndDiscoverMember(headlessSerial, groupId, inviteCode, new Set([t0.uid, t1Uid]), t0.token);
  console.log(`  T2 uid ${t2Uid} joined on ${headlessSerial}`);

  console.log('\nHanding ownership to the visible emulator (T1)...');
  await fsRequest('PATCH', `groups/${groupId}/members/${t1Uid}`, {
    token: t0.token,
    query: 'updateMask.fieldPaths=role',
    body: { fields: fsFields({ role: 'owner' }) },
  });
  await fsRequest('PATCH', `groups/${groupId}`, {
    token: t0.token,
    query: 'updateMask.fieldPaths=ownerId',
    body: { fields: fsFields({ ownerId: t1Uid }) },
  });
  await fsRequest('PATCH', `groups/${groupId}/members/${t0.uid}`, {
    token: t0.token,
    query: 'updateMask.fieldPaths=role',
    body: { fields: fsFields({ role: 'member' }) },
  });

  console.log('\nGranting location permission + starting sharing on both real emulators...');
  adb(VISIBLE_SERIAL, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_FINE_LOCATION');
  adb(VISIBLE_SERIAL, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_COARSE_LOCATION');
  try {
    adb(VISIBLE_SERIAL, 'shell', 'pm', 'grant', PACKAGE, 'android.permission.ACCESS_BACKGROUND_LOCATION');
  } catch (_) {}
  // Give the map screen (and its auto-fit camera animation) a moment to
  // settle after the join before probing for the FAB.
  await sleep(3000);
  await ensureSharingStarted(VISIBLE_SERIAL, 'T1 (visible)');
  await ensureSharingStarted(headlessSerial, 'T2 (headless)');

  console.log(`\nStarting movement simulation - ${SPEED_MPH}mph, real-time, ${TICK_SECONDS}s ticks.`);
  console.log('Watch the visible emulator - it is the owner (T1). Ctrl+C to stop early.\n');

  const travelers = [
    { label: 'T0 (ghost)', uid: t0.uid, token: t0.token, mode: 'rest', start: starts[0], totalKm: totalDistanceKm[0] },
    { label: 'T1 (visible)', uid: t1Uid, mode: 'emu', serial: VISIBLE_SERIAL, start: starts[1], totalKm: totalDistanceKm[1] },
    { label: 'T2 (headless)', uid: t2Uid, mode: 'emu', serial: headlessSerial, start: starts[2], totalKm: totalDistanceKm[2] },
  ];

  const startTime = Date.now();
  const capMs = SAFETY_CAP_MINUTES * 60 * 1000;
  let allArrived = false;
  while (!allArrived && Date.now() - startTime < capMs) {
    const elapsedHours = (Date.now() - startTime) / 3600000;
    const traveledKm = SPEED_MPH * MILES_TO_KM * elapsedHours;
    allArrived = true;
    const statusParts = [];
    for (const t of travelers) {
      const fraction = Math.min(1, traveledKm / t.totalKm);
      if (fraction < 1) allArrived = false;
      const pos = lerpPoint(t.start, DESTINATION, fraction);
      const remainingMi = (t.totalKm * (1 - fraction)) / MILES_TO_KM;
      statusParts.push(`${t.label}: ${remainingMi.toFixed(2)}mi left`);

      if (t.mode === 'rest') {
        await fsRequest('PATCH', `groups/${groupId}/locations/${t.uid}`, {
          token: t.token,
          body: {
            fields: fsFields({
              displayName: 'Ghost traveler',
              lat: pos.lat,
              lng: pos.lng,
              heading: bearingDeg(pos, DESTINATION),
              speed: SPEED_MPH * 0.44704,
              updatedAt: new Date(),
            }),
          },
        });
      } else {
        adb(t.serial, 'emu', 'geo', 'fix', String(pos.lng), String(pos.lat));
      }
    }
    console.log(statusParts.join('  |  '));
    await sleep(TICK_SECONDS * 1000);
  }

  console.log(allArrived ? '\nAll 3 travelers have reached the destination.' : '\nSafety time cap reached.');
  console.log(`Group id: ${groupId}   Invite code: ${inviteCode}`);
}

main().catch((err) => {
  console.error('\nFAILED:', err);
  process.exit(1);
});
