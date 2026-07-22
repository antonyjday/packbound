/**
 * All the tunable timing thresholds for group lifecycle/cleanup in one
 * place. Adjust these rather than hunting through function bodies.
 */

// A group with no location writes for this long is assumed to be an
// abandoned/finished trip and gets auto-ended. Set a bit above a typical
// overnight rest stop so a multi-day convoy parked for the night doesn't
// get swept just for being quiet - but note this is still shorter than
// most overnight stops, which is exactly why the expiry warnings below
// exist: the owner should extend *before* stopping for the night if the
// convoy will resume the next day.
export const INACTIVITY_TIMEOUT_HOURS = 10;

// How long a trip lasts by default from creation, and how long each
// owner-triggered extension adds. A trip that hits this limit is
// force-ended regardless of activity - it's a hard cap, not a guess.
export const TRIP_LIFETIME_HOURS = 24;
export const EXTENSION_HOURS = 24;

// Warning lead times before the hard cap (TRIP_LIFETIME_HOURS / an
// extension) is reached. Two stages: an early heads-up while there's
// still time to comfortably extend, and a final urgent nudge.
export const EARLY_WARNING_LEAD_HOURS = 4;
export const FINAL_WARNING_LEAD_HOURS = 1;

// How long to keep an ended group's metadata around (for things like
// "recent trips" history) before permanently deleting the group doc
// and any remaining subcollections.
export const RETENTION_DAYS_AFTER_END = 30;

// How often the inactivity sweep runs. Shorter = more responsive
// auto-ending, but more scheduled invocations.
export const INACTIVITY_SWEEP_SCHEDULE = 'every 30 minutes';

// How often the expiry-warning sweep runs - independent of the
// inactivity sweep since warnings need finer granularity near the
// deadline than the 30 min inactivity check requires.
export const WARNING_SWEEP_SCHEDULE = 'every 15 minutes';

// How often the permanent-purge sweep runs. This is low-frequency
// since 30-day-old data isn't time-sensitive to remove promptly.
export const PURGE_SWEEP_SCHEDULE = 'every 24 hours';

// How long a member's location can go without an update before the rest
// of the group gets a push about it. Deliberately longer than the
// in-app "lost" signal status (60s, see LocationPoint.status in the
// Flutter client) - that's a passive UI color change fine to show
// eagerly, but a disruptive push notification needs a longer, calmer
// threshold so a brief tunnel/elevator signal drop doesn't page everyone.
export const SIGNAL_LOST_NOTIFY_MINUTES = 5;

// How often the signal-lost sweep runs. Detection latency is up to this
// interval on top of SIGNAL_LOST_NOTIFY_MINUTES itself, so keep it short
// relative to that threshold.
export const SIGNAL_LOST_SWEEP_SCHEDULE = 'every 5 minutes';

// How close to the route's destination counts as "arrived" for the
// arrival push notification. Mirrors waypointArrivalRadiusMeters in the
// Flutter client's lib/utils/route_progress.dart.
export const ARRIVAL_RADIUS_METERS = 500;
