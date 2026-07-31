import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import { onDocumentWritten, onDocumentUpdated, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import {
  INACTIVITY_TIMEOUT_HOURS,
  EARLY_WARNING_LEAD_HOURS,
  FINAL_WARNING_LEAD_HOURS,
  RETENTION_DAYS_AFTER_END,
  INACTIVITY_SWEEP_SCHEDULE,
  WARNING_SWEEP_SCHEDULE,
  PURGE_SWEEP_SCHEDULE,
  SIGNAL_LOST_NOTIFY_MINUTES,
  SIGNAL_LOST_SWEEP_SCHEDULE,
  ARRIVAL_RADIUS_METERS,
  USER_PROFILE_RETENTION_DAYS,
  USER_PROFILE_PURGE_SCHEDULE,
} from './config';

initializeApp();
const db = getFirestore();

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const MINUTE_MS = 60 * 1000;
const EARTH_RADIUS_METERS = 6371000;

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(a));
}

/**
 * Sends a push notification to every member of a group (optionally
 * excluding one, e.g. the member the notification is *about* rather than
 * *for*). Tokens come from `users/{uid}.fcmToken`, written by the
 * client's NotificationService whenever it has a signed-in user.
 * Best-effort: a failed/partial send is logged, never thrown, so it
 * can't abort whatever sweep/trigger called it.
 */
async function sendPushToGroupMembers(
  groupId: string,
  { title, body, excludeUid }: { title: string; body: string; excludeUid?: string }
) {
  try {
    const membersSnap = await db.collection('groups').doc(groupId).collection('members').get();
    if (membersSnap.empty) return;

    const memberIds = membersSnap.docs.map((d) => d.id).filter((id) => id !== excludeUid);
    if (memberIds.length === 0) return;

    const userRefs = memberIds.map((id) => db.collection('users').doc(id));
    const userDocs = await db.getAll(...userRefs);
    const tokens = userDocs
      .map((doc) => doc.get('fcmToken') as string | undefined)
      .filter((token): token is string => !!token);

    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
    });
    logger.info(
      `sendPushToGroupMembers: sent to ${response.successCount}/${tokens.length} for group ${groupId}`
    );
  } catch (err) {
    logger.error(`sendPushToGroupMembers: failed for group ${groupId}`, err);
  }
}

/**
 * Every time a member writes their location, bump the parent group's
 * `lastActivityAt`. This is what the inactivity sweep checks against -
 * a convoy is "alive" as long as *someone* in it is still sharing.
 *
 * Deliberately cheap: one extra field write per location update,
 * triggered on the same event that's already happening.
 */
export const trackGroupActivity = onDocumentWritten(
  'groups/{groupId}/locations/{userId}',
  async (event) => {
    const { groupId } = event.params;
    await db.collection('groups').doc(groupId).update({
      lastActivityAt: Timestamp.now(),
    });
  }
);

/**
 * Scheduled sweep: finds groups that are still marked `active` but have
 * gone quiet, and ends them. Two conditions, either one ends a group:
 *   1. No location activity for INACTIVITY_TIMEOUT_HOURS - trip is over.
 *   2. `tripExpiresAt` has passed - the hard cap the owner can push back
 *      via the "extend trip" action, but which otherwise ends the group
 *      regardless of activity so a convoy can never run forever.
 */
export const endInactiveGroups = onSchedule(INACTIVITY_SWEEP_SCHEDULE, async () => {
  const now = Timestamp.now();
  const inactivityCutoff = Timestamp.fromMillis(now.toMillis() - INACTIVITY_TIMEOUT_HOURS * HOUR_MS);

  const [inactiveSnap, expiredSnap] = await Promise.all([
    db.collection('groups')
      .where('status', '==', 'active')
      .where('lastActivityAt', '<=', inactivityCutoff)
      .get(),
    db.collection('groups')
      .where('status', '==', 'active')
      .where('tripExpiresAt', '<=', now)
      .get(),
  ]);

  const endedReasons = new Map<string, string>();
  inactiveSnap.docs.forEach((d) => endedReasons.set(d.id, 'auto_inactivity'));
  // If both conditions apply, the hard cap is the more informative reason to show the group.
  expiredSnap.docs.forEach((d) => endedReasons.set(d.id, 'trip_expired'));

  if (endedReasons.size === 0) {
    logger.info('endInactiveGroups: nothing to end');
    return;
  }

  const batch = db.batch();
  endedReasons.forEach((reason, groupId) => {
    batch.update(db.collection('groups').doc(groupId), {
      status: 'ended',
      endedAt: Timestamp.now(),
      endedReason: reason,
    });
  });
  await batch.commit();

  logger.info(`endInactiveGroups: ended ${endedReasons.size} group(s)`, {
    groupIds: Array.from(endedReasons.keys()),
  });
});

/**
 * Pushes a trip-expiry warning to every member of a group (not just the
 * owner) - matches who already sees the in-app banner in MapScreen, where
 * the owner gets an "Extend" action and everyone else is told to ask them.
 */
async function sendExpiryWarningPush(groupId: string, groupName: string, level: number) {
  const urgent = level === 2;
  const title = urgent ? 'Trip ending very soon' : 'Trip ending soon';
  const body = urgent
    ? `"${groupName}" ends in about ${FINAL_WARNING_LEAD_HOURS}h. Extend it now if you're not done.`
    : `"${groupName}" ends in about ${EARLY_WARNING_LEAD_HOURS}h. The owner can extend it from the app.`;
  await sendPushToGroupMembers(groupId, { title, body });
}

/**
 * Scheduled sweep: gives the owner fair warning before `tripExpiresAt`
 * hits, so a convoy that's stopped for the night (and will resume the
 * next day) doesn't get quietly force-ended while everyone's asleep.
 * Two stages, tracked via `expiryWarningLevel` so each is only sent
 * once per stage:
 *   1 = early warning (EARLY_WARNING_LEAD_HOURS out)
 *   2 = final warning (FINAL_WARNING_LEAD_HOURS out)
 *
 * Sets the Firestore fields the in-app banner (MapScreen) reads, and also
 * pushes a notification via sendExpiryWarningPush for members who aren't
 * looking at the app right now.
 */
export const warnExpiringGroups = onSchedule(WARNING_SWEEP_SCHEDULE, async () => {
  const now = Timestamp.now();
  const earlyCutoff = Timestamp.fromMillis(now.toMillis() + EARLY_WARNING_LEAD_HOURS * HOUR_MS);
  const finalCutoff = Timestamp.fromMillis(now.toMillis() + FINAL_WARNING_LEAD_HOURS * HOUR_MS);

  const [needsFinalSnap, needsEarlySnap] = await Promise.all([
    db.collection('groups')
      .where('status', '==', 'active')
      .where('tripExpiresAt', '<=', finalCutoff)
      .where('expiryWarningLevel', '<', 2)
      .get(),
    db.collection('groups')
      .where('status', '==', 'active')
      .where('tripExpiresAt', '<=', earlyCutoff)
      .where('expiryWarningLevel', '<', 1)
      .get(),
  ]);

  const batch = db.batch();
  let count = 0;

  needsFinalSnap.docs.forEach((d) => {
    batch.update(d.ref, { expiryWarningLevel: 2, expiryWarningAt: now });
    count++;
  });
  // Only bump docs to level 1 if they weren't just bumped to level 2 above.
  const finalIds = new Set(needsFinalSnap.docs.map((d) => d.id));
  needsEarlySnap.docs.forEach((d) => {
    if (finalIds.has(d.id)) return;
    batch.update(d.ref, { expiryWarningLevel: 1, expiryWarningAt: now });
    count++;
  });

  if (count === 0) {
    logger.info('warnExpiringGroups: nothing to warn');
    return;
  }

  await Promise.all([
    batch.commit(),
    ...needsFinalSnap.docs.map((d) => sendExpiryWarningPush(d.id, d.data().name, 2)),
    ...needsEarlySnap.docs
      .filter((d) => !finalIds.has(d.id))
      .map((d) => sendExpiryWarningPush(d.id, d.data().name, 1)),
  ]);

  logger.info(`warnExpiringGroups: flagged ${count} group(s) for expiry warning`);
});

/**
 * Fires whenever a group document is updated. If `status` just
 * transitioned to 'ended' (whether by the owner tapping "end trip" or
 * by the scheduled sweep above), immediately delete the live location
 * data - there's no reason to keep broadcasting or retaining precise
 * positions once a trip is over. Membership records are kept (for
 * trip history) but locations and quick-messages are wiped since they're
 * the sensitive/time-sensitive parts.
 */
export const cleanupEndedGroupData = onDocumentUpdated('groups/{groupId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const justEnded = before.status !== 'ended' && after.status === 'ended';
  if (!justEnded) return;

  const { groupId } = event.params;
  const groupRef = db.collection('groups').doc(groupId);

  await Promise.all([
    db.recursiveDelete(groupRef.collection('locations')),
    db.recursiveDelete(groupRef.collection('messages')),
    // Voice clips (see VoiceMessageService) live in Storage, not
    // Firestore - recursiveDelete above only clears the message docs
    // that reference them, so the audio files need deleting separately
    // or they'd linger in Storage forever.
    getStorage().bucket().deleteFiles({ prefix: `groups/${groupId}/voice/` })
      .catch((err) => logger.warn(`cleanupEndedGroupData: voice clip cleanup failed for group ${groupId}`, err)),
  ]);

  logger.info(`cleanupEndedGroupData: purged locations/messages/voice for group ${groupId}`);
});

/**
 * Daily sweep: permanently deletes groups (and any remaining
 * subcollections - members, etc.) that have been in 'ended' state
 * longer than the retention window. This is the final cleanup step so
 * old trip data doesn't accumulate indefinitely.
 */
export const purgeOldEndedGroups = onSchedule(PURGE_SWEEP_SCHEDULE, async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - RETENTION_DAYS_AFTER_END * DAY_MS);

  const snap = await db.collection('groups')
    .where('status', '==', 'ended')
    .where('endedAt', '<=', cutoff)
    .get();

  if (snap.empty) {
    logger.info('purgeOldEndedGroups: nothing to purge');
    return;
  }

  await Promise.all(snap.docs.map((doc) => db.recursiveDelete(doc.ref)));

  logger.info(`purgeOldEndedGroups: permanently deleted ${snap.size} group(s)`, {
    groupIds: snap.docs.map((d) => d.id),
  });
});

/**
 * Scheduled sweep: finds members whose location hasn't updated in
 * SIGNAL_LOST_NOTIFY_MINUTES and pushes the rest of their group about it.
 * Queries across every group's `locations` subcollection at once via a
 * collection-group query - a location doc surviving at all implies its
 * group is still active, since cleanupEndedGroupData recursively deletes
 * a group's locations the moment it ends, so there's no need to
 * cross-check group status here.
 *
 * `signalLostNotifiedForUpdatedAt` (stored on the location doc itself)
 * tracks which exact `updatedAt` a notification was already sent for -
 * once the member sends a fresh location update, `updatedAt` moves on
 * and no longer matches, so a *later* staleness naturally notifies again
 * without needing a separate "reset on recovery" pass.
 */
export const notifyLostSignals = onSchedule(SIGNAL_LOST_SWEEP_SCHEDULE, async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - SIGNAL_LOST_NOTIFY_MINUTES * MINUTE_MS);

  const staleSnap = await db.collectionGroup('locations').where('updatedAt', '<=', cutoff).get();
  if (staleSnap.empty) {
    logger.info('notifyLostSignals: nothing stale');
    return;
  }

  let notifiedCount = 0;
  await Promise.all(
    staleSnap.docs.map(async (doc) => {
      const data = doc.data();
      const updatedAt = data.updatedAt as Timestamp | undefined;
      if (!updatedAt) return;
      if (data.signalLostNotifiedForUpdatedAt?.isEqual?.(updatedAt)) return;

      const groupId = doc.ref.parent.parent?.id;
      if (!groupId) return;

      await doc.ref.update({ signalLostNotifiedForUpdatedAt: updatedAt });
      await sendPushToGroupMembers(groupId, {
        title: 'Signal lost',
        body: `${data.displayName ?? 'A member'}'s location hasn't updated in a while.`,
        excludeUid: doc.id,
      });
      notifiedCount++;
    })
  );

  logger.info(`notifyLostSignals: notified for ${notifiedCount} stale member(s)`);
});

/**
 * Fires on every location write. If the group has a route and this
 * member's new position is within ARRIVAL_RADIUS_METERS of the
 * destination, pushes the rest of the group about it.
 *
 * `arrivedNotifiedForRouteSetAt` (stored on the location doc) tracks
 * which route version - identified by the group's `route.setAt` - an
 * arrival was already sent for. If the owner sets a new route later
 * (different `setAt`), a fresh arrival at the new destination can notify
 * again rather than staying permanently suppressed by an old arrival.
 */
export const notifyOnArrival = onDocumentWritten(
  'groups/{groupId}/locations/{userId}',
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return; // location doc deleted (left/removed)

    const location = after.data()!;
    const { groupId, userId } = event.params;

    const groupSnap = await db.collection('groups').doc(groupId).get();
    const route = groupSnap.data()?.route as
      | { destination?: { lat: number; lng: number }; setAt?: Timestamp }
      | undefined;
    const destination = route?.destination;
    if (!destination || !route?.setAt) return; // no route set

    const alreadyNotified = (location.arrivedNotifiedForRouteSetAt as Timestamp | undefined)?.isEqual?.(
      route.setAt
    );
    if (alreadyNotified) return;

    const distanceMeters = haversineMeters(
      location.lat,
      location.lng,
      destination.lat,
      destination.lng
    );
    if (distanceMeters > ARRIVAL_RADIUS_METERS) return;

    await after.ref.update({ arrivedNotifiedForRouteSetAt: route.setAt });
    await sendPushToGroupMembers(groupId, {
      title: 'Arrived',
      body: `${location.displayName ?? 'A member'} has arrived at the destination.`,
      excludeUid: userId,
    });
  }
);

/**
 * Fires on every quick-message sent (see GroupService.sendQuickMessage) -
 * pushes it to the rest of the group, same as the other notifications
 * above, so a preset message like "Pulling over" reaches members who
 * aren't currently looking at the app.
 */
export const notifyOnQuickMessage = onDocumentCreated(
  'groups/{groupId}/messages/{messageId}',
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const { groupId } = event.params;
    await sendPushToGroupMembers(groupId, {
      title: message.senderName ?? 'New message',
      body: message.audioUrl ? '🎤 Voice message' : (message.text ?? ''),
      excludeUid: message.senderId,
    });
  }
);

/**
 * Daily sweep: permanently deletes `users/{uid}` profile docs (display
 * name, lastSeen, push token) that have gone untouched for
 * USER_PROFILE_RETENTION_DAYS. This doc isn't part of any group's
 * subcollections, so nothing above ever cleans it up - a device that
 * signs in once and never returns would otherwise keep a profile forever.
 * `lastSeen` is bumped by AuthService.updateLastSeen() on every app open,
 * not just first sign-in, so staleness here really does mean "not opened
 * in USER_PROFILE_RETENTION_DAYS", not "hasn't started a new trip".
 * This is the automatic backstop referenced on packbound.net/delete-data -
 * an emailed deletion request is actioned immediately by hand, but this
 * sweep means the data doesn't linger indefinitely even if nobody asks.
 */
export const purgeStaleUserProfiles = onSchedule(USER_PROFILE_PURGE_SCHEDULE, async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - USER_PROFILE_RETENTION_DAYS * DAY_MS);

  const snap = await db.collection('users').where('lastSeen', '<=', cutoff).get();

  if (snap.empty) {
    logger.info('purgeStaleUserProfiles: nothing to purge');
    return;
  }

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  logger.info(`purgeStaleUserProfiles: permanently deleted ${snap.size} stale profile(s)`);
});
