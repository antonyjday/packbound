import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentWritten, onDocumentUpdated } from 'firebase-functions/v2/firestore';
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
} from './config';

initializeApp();
const db = getFirestore();

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

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
 * Tokens come from `users/{uid}.fcmToken`, written by the client's
 * NotificationService whenever it has a signed-in user. Best-effort: a
 * failed/partial send is logged, never thrown, so it can't abort the
 * caller's sweep over the rest of the warned groups.
 */
async function sendExpiryWarningPush(groupId: string, groupName: string, level: number) {
  try {
    const membersSnap = await db.collection('groups').doc(groupId).collection('members').get();
    if (membersSnap.empty) return;

    const userRefs = membersSnap.docs.map((d) => db.collection('users').doc(d.id));
    const userDocs = await db.getAll(...userRefs);
    const tokens = userDocs
      .map((doc) => doc.get('fcmToken') as string | undefined)
      .filter((token): token is string => !!token);

    if (tokens.length === 0) return;

    const urgent = level === 2;
    const title = urgent ? 'Trip ending very soon' : 'Trip ending soon';
    const body = urgent
      ? `"${groupName}" ends in about ${FINAL_WARNING_LEAD_HOURS}h. Extend it now if you're not done.`
      : `"${groupName}" ends in about ${EARLY_WARNING_LEAD_HOURS}h. The owner can extend it from the app.`;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
    });
    logger.info(
      `sendExpiryWarningPush: sent to ${response.successCount}/${tokens.length} for group ${groupId}`
    );
  } catch (err) {
    logger.error(`sendExpiryWarningPush: failed for group ${groupId}`, err);
  }
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
 * trip history) but locations are wiped since they're the sensitive,
 * time-sensitive part.
 */
export const cleanupEndedGroupData = onDocumentUpdated('groups/{groupId}', async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const justEnded = before.status !== 'ended' && after.status === 'ended';
  if (!justEnded) return;

  const { groupId } = event.params;
  const locationsRef = db.collection('groups').doc(groupId).collection('locations');

  await db.recursiveDelete(locationsRef);

  logger.info(`cleanupEndedGroupData: purged locations for group ${groupId}`);
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
