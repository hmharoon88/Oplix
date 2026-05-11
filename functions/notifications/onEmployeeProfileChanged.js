/**
 * Cloud Function: notify an employee when either their schedule or
 * their location assignments change.
 *
 * Trigger: master-level employee doc:
 *     users/{managerId}/employees/{employeeId}
 *
 * Why master-level (not the per-location mirror):
 *   - The master doc is written once per edit, regardless of how
 *     many locations the employee is assigned to. Listening here
 *     prevents the same edit from firing N notifications when the
 *     change is propagated to N location-level mirrors.
 *
 * One function, two distinct notification categories:
 *   - `weeklySchedule` change → category: 'schedule'
 *   - `assignedLocationIds` change → category: 'assignment'
 *
 * They route through the same trigger but go through `sendPushToUser`
 * with different `category` values, so users can opt out of one
 * without affecting the other.
 */

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {sendPushToUser} = require('./sendPush');

/**
 * Compare two values for equality, treating `undefined` and `null`
 * as the same and using JSON-shape compare for objects/arrays. We
 * deliberately don't import a deep-equal lib for one tiny use case;
 * `JSON.stringify` is good enough here because both sides are
 * plain JSON-serialised Firestore values.
 */
function shallowEqualJSON(a, b) {
  const aSerialised = a === undefined || a === null ? null : JSON.stringify(a);
  const bSerialised = b === undefined || b === null ? null : JSON.stringify(b);
  return aSerialised === bSerialised;
}

/**
 * Detect whether `assignedLocationIds` actually changed.
 * Order-insensitive — adding then removing the same id in one
 * write counts as no change.
 */
function locationsActuallyChanged(before, after) {
  const beforeSet = new Set(Array.isArray(before) ? before : []);
  const afterSet = new Set(Array.isArray(after) ? after : []);
  if (beforeSet.size !== afterSet.size) return true;
  for (const id of beforeSet) {
    if (!afterSet.has(id)) return true;
  }
  return false;
}

/**
 * Diff helpers for what to surface to the employee. We don't go into
 * "monday's start time changed by 15 minutes" detail in the push
 * body — too fragile and noisy. Just announce the category and the
 * employee can open the app to see the new schedule.
 */
function scheduleChanged(beforeData, afterData) {
  return !shallowEqualJSON(beforeData?.weeklySchedule, afterData?.weeklySchedule);
}

function assignmentDelta(beforeData, afterData) {
  const before = beforeData?.assignedLocationIds || [];
  const after = afterData?.assignedLocationIds || [];
  if (!locationsActuallyChanged(before, after)) {
    return {changed: false};
  }
  const beforeSet = new Set(before);
  const afterSet = new Set(after);
  return {
    changed: true,
    added: after.filter((id) => !beforeSet.has(id)),
    removed: before.filter((id) => !afterSet.has(id)),
  };
}

exports.onEmployeeProfileChanged = onDocumentWritten(
    {
      document: 'users/{managerId}/employees/{employeeId}',
      region: 'us-central1',
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();

      // Doc deletion — handled elsewhere (deleteUserOnUserDocumentDelete).
      if (!afterData) return;

      // Doc creation — the employee was just created. We deliberately
      // skip notifying here because:
      //   - The Auth account they sign into is created in the same
      //     transaction; notifying before they sign in is wasted spend.
      //   - The "welcome" experience is better handled separately
      //     (email, manager-initiated invite, etc.) than via push.
      if (!beforeData) return;

      const {managerId, employeeId} = event.params;

      const tasks = [];

      if (scheduleChanged(beforeData, afterData)) {
        tasks.push(sendPushToUser({
          userId: employeeId,
          category: 'schedule',
          title: 'Your schedule was updated',
          body: 'Your manager updated your weekly schedule. Tap to review.',
          data: {
            subtype: 'schedule_changed',
            managerId,
            employeeId,
          },
        }).then((result) => {
          logResult('schedule', employeeId, result);
        }).catch((err) => {
          console.error(`🔴 Schedule push failed for ${employeeId}:`, err);
        }));
      }

      const assignment = assignmentDelta(beforeData, afterData);
      if (assignment.changed) {
        tasks.push(sendPushToUser({
          userId: employeeId,
          category: 'assignment',
          title: 'Your location assignments changed',
          body: assignmentBody(assignment),
          data: {
            subtype: 'assignment_changed',
            managerId,
            employeeId,
            added: (assignment.added || []).join(','),
            removed: (assignment.removed || []).join(','),
          },
        }).then((result) => {
          logResult('assignment', employeeId, result);
        }).catch((err) => {
          console.error(`🔴 Assignment push failed for ${employeeId}:`, err);
        }));
      }

      if (tasks.length === 0) return;
      await Promise.all(tasks);
    },
);

function logResult(label, employeeId, result) {
  if (result.skipped) {
    console.log(`📭 ${label} push to ${employeeId} skipped: ${result.skipped}`);
  } else {
    console.log(`📨 ${label} push → ${employeeId} (sent=${result.sent}, dead=${result.dead})`);
  }
}

function assignmentBody({added, removed}) {
  const a = (added || []).length;
  const r = (removed || []).length;
  if (a > 0 && r === 0) {
    return a === 1 ? 'You were added to a new location.' : `You were added to ${a} new locations.`;
  }
  if (r > 0 && a === 0) {
    return r === 1 ? 'You were removed from a location.' : `You were removed from ${r} locations.`;
  }
  // Mixed (added + removed in the same edit)
  return 'Your location assignments were updated.';
}

module.exports.__test__ = {scheduleChanged, assignmentDelta, locationsActuallyChanged};
