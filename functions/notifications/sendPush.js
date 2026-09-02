/**
 * Shared push notification helper.
 *
 * Encapsulates everything that's the same across every "send a push"
 * code path:
 *   - Look up the recipient user's `notificationPrefs` and respect
 *     the channel master toggle, the per-category toggle, and quiet
 *     hours.
 *   - Enumerate every device the user has registered (per-device
 *     subcollection at users/{userId}/fcmTokens) and fan out one
 *     FCM `send()` call per token.
 *   - Auto-clean stale tokens — when FCM tells us a token is no
 *     longer registered, delete that doc so the user's inbox stays
 *     accurate without anyone having to garbage-collect manually.
 *
 * The category gating is the contract that makes the in-app Settings
 * screen actually mean something: if `notificationPrefs.categories
 * .tasks === false`, we silently skip rather than send.
 */

const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');

/**
 * Categories must match the keys defined in the Swift `NotificationPrefs.Categories`
 * struct. Adding one here without adding it on the iOS side won't break
 * anything (an unknown category just defaults to "on" because the resolved
 * lookups treat absence as `true`), but they'll diverge for opt-out
 * purposes — keep them in sync.
 */
const KNOWN_CATEGORIES = new Set([
  'tasks',
  'schedule',
  'assignment',
  'shiftSummary',
  'cashAlert',
  'financeAlert',
  'complianceAlert',
  'dueReminder',
  'dailyDigest',
]);

/**
 * Default values for missing preferences. Mirrors the `resolved*`
 * accessors on the Swift side so server and client agree on what a
 * blank/absent prefs map means: everything on except `dailyDigest`.
 */
function resolveBool(value, fallback) {
  if (typeof value === 'boolean') return value;
  return fallback;
}

/**
 * Whether `nowMinutes` falls inside the user's configured quiet
 * hours window. The window can wrap past midnight (e.g. 22:00–07:00),
 * so we need both contained-range and wrapping-range cases.
 */
function isInsideQuietHours(quiet, nowMinutes) {
  if (!quiet || !resolveBool(quiet.enabled, false)) return false;
  const start = typeof quiet.startMin === 'number' ? quiet.startMin : 22 * 60;
  const end = typeof quiet.endMin === 'number' ? quiet.endMin : 7 * 60;
  if (start === end) return false;
  if (start < end) {
    return nowMinutes >= start && nowMinutes < end;
  }
  // Wrapping window (e.g. 22:00–07:00).
  return nowMinutes >= start || nowMinutes < end;
}

/**
 * Convert a Date to "minutes from midnight" in the manager's
 * timezone — for now we just use server UTC since the app doesn't
 * track per-user timezone. Good enough for the MVP; we can layer
 * timezone-aware quiet hours later without changing the API.
 */
function nowAsMinutes(date = new Date()) {
  return date.getUTCHours() * 60 + date.getUTCMinutes();
}

/**
 * Decide whether to send a notification of `category` to the user
 * whose User doc is `userData`. Returns a reason string when we're
 * skipping (logged for observability); returns null when we should
 * proceed.
 */
function pushBlockReason(userData, category) {
  const prefs = (userData && userData.notificationPrefs) || {};
  const channels = prefs.channels || {};
  const categories = prefs.categories || {};
  const quiet = prefs.quietHours || {};

  if (!resolveBool(channels.push, true)) {
    return 'channel_push_off';
  }
  if (KNOWN_CATEGORIES.has(category)) {
    const fallback = category === 'dailyDigest' ? false : true;
    if (!resolveBool(categories[category], fallback)) {
      return `category_${category}_off`;
    }
  }
  if (isInsideQuietHours(quiet, nowAsMinutes())) {
    return 'quiet_hours';
  }
  return null;
}

/**
 * Fetch a user doc from Firestore. Returns null if the user has been
 * deleted between trigger fire and helper invocation — caller should
 * skip silently.
 */
async function loadUser(userId) {
  const db = getFirestore();
  const snap = await db.collection('users').doc(userId).get();
  return snap.exists ? snap.data() : null;
}

/**
 * Fetch every FCM token registered for this user. Returns an array
 * of {deviceId, token} pairs so caller can clean specific docs by
 * id when their token rejects.
 */
async function loadDeviceTokens(userId) {
  const db = getFirestore();
  const snap = await db
      .collection('users')
      .doc(userId)
      .collection('fcmTokens')
      .get();
  return snap.docs
      .map((d) => ({deviceId: d.id, token: d.data().token}))
      .filter((entry) => typeof entry.token === 'string' && entry.token.length > 0);
}

/**
 * Device ids + raw FCM tokens registered on an owner/manager account.
 * Assignment pushes skip these so a shared phone doesn't ring for the
 * owner when an employee is assigned.
 */
async function loadOwnerTokenFilters(ownerUserId) {
  if (!ownerUserId) {
    return {deviceIds: new Set(), tokens: new Set()};
  }
  const entries = await loadDeviceTokens(ownerUserId);
  return {
    deviceIds: new Set(entries.map((e) => e.deviceId)),
    tokens: new Set(entries.map((e) => e.token)),
  };
}

function filterExcludedTokens(tokens, excludeDeviceIds, excludeTokens) {
  let filtered = tokens;
  if (excludeDeviceIds && excludeDeviceIds.size > 0) {
    filtered = filtered.filter((entry) => !excludeDeviceIds.has(entry.deviceId));
  }
  if (excludeTokens && excludeTokens.size > 0) {
    filtered = filtered.filter((entry) => !excludeTokens.has(entry.token));
  }
  return filtered;
}

/**
 * FCM error codes that mean "this token is dead — stop sending to it".
 * https://firebase.google.com/docs/cloud-messaging/send-message#admin
 */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

async function deleteDeadToken(userId, deviceId) {
  try {
    await getFirestore()
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(deviceId)
        .delete();
  } catch (err) {
    // Cleanup is best-effort — log but don't blow up the calling function.
    console.warn(`⚠️ Failed to clean dead token ${userId}/${deviceId}:`, err.message);
  }
}

/**
 * Send a push notification to one user across all of their devices.
 *
 * @param {object} args
 * @param {string} args.userId          - recipient user id (Firebase Auth uid)
 * @param {string} args.category        - one of KNOWN_CATEGORIES
 * @param {string} args.title           - notification title
 * @param {string} args.body            - notification body
 * @param {object} [args.data]          - custom payload merged into FCM `data`
 *                                        (used by the iOS tap handler for routing)
 * @param {Set<string>} [args.excludeDeviceIds] - skip these device doc ids
 * @param {Set<string>} [args.excludeTokens]    - skip these raw FCM tokens
 * @returns {Promise<{sent: number, skipped: string|null, dead: number}>}
 */
async function sendPushToUser({
  userId,
  category,
  title,
  body,
  data = {},
  excludeDeviceIds,
  excludeTokens,
}) {
  if (!userId) {
    return {sent: 0, skipped: 'no_user', dead: 0};
  }

  const user = await loadUser(userId);
  if (!user) {
    return {sent: 0, skipped: 'user_not_found', dead: 0};
  }

  const blockReason = pushBlockReason(user, category);
  if (blockReason) {
    return {sent: 0, skipped: blockReason, dead: 0};
  }

  const tokens = filterExcludedTokens(
      await loadDeviceTokens(userId),
      excludeDeviceIds,
      excludeTokens,
  );
  if (tokens.length === 0) {
    return {sent: 0, skipped: 'no_tokens', dead: 0};
  }

  // FCM data values must be strings. Stringify everything so callers
  // don't need to remember.
  const stringifiedData = Object.fromEntries(
      Object.entries({category, ...data}).map(([k, v]) => [k, String(v ?? '')]),
  );

  const messaging = getMessaging();
  let sent = 0;
  let dead = 0;

  await Promise.all(tokens.map(async ({deviceId, token}) => {
    try {
      await messaging.send({
        token,
        notification: {title, body},
        data: stringifiedData,
        android: {
          priority: 'high',
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: {title, body},
              sound: 'default',
            },
          },
        },
      });
      sent += 1;
    } catch (err) {
      if (DEAD_TOKEN_CODES.has(err.code)) {
        await deleteDeadToken(userId, deviceId);
        dead += 1;
      } else {
        console.warn(`⚠️ FCM send failed for ${userId}/${deviceId} (${err.code}):`, err.message);
      }
    }
  }));

  // Touch the user doc with a `lastPushAt` for observability — purely
  // additive, so existing data is unaffected. Ignored if the doc has
  // been deleted (race) by the catch.
  try {
    await getFirestore()
        .collection('users')
        .doc(userId)
        .update({lastPushAt: FieldValue.serverTimestamp()});
  } catch (_) {
    // best-effort
  }

  return {sent, skipped: null, dead};
}

module.exports = {
  sendPushToUser,
  loadOwnerTokenFilters,
  // Exported for unit tests / future helpers
  __test__: {pushBlockReason, isInsideQuietHours, nowAsMinutes, filterExcludedTokens},
};
