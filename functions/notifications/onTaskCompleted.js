/**
 * Cloud Function: notify manager + location supervisors when an
 * employee submits a task completion (photo proof).
 *
 * Trigger: location-level task doc (same path as onTaskAssigned /
 * onTaskReviewed):
 *     users/{managerId}/locations/{locationId}/tasks/{taskId}
 *
 * We diff `employeeCompletions` and only notify when an employee
 * submits a **new** completion (new employeeId or newer timestamp).
 * Review-only edits (isApproved / reviewedAt) reuse the same timestamp
 * and do not re-notify.
 */

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {getFirestore} = require('firebase-admin/firestore');
const {sendPushToUser} = require('./sendPush');

function completionTimestampMs(completion) {
  if (!completion?.timestamp) return null;
  const ts = completion.timestamp;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts._seconds != null) return ts._seconds * 1000 + (ts._nanoseconds || 0) / 1e6;
  if (ts.seconds != null) return ts.seconds * 1000 + (ts.nanoseconds || 0) / 1e6;
  if (typeof ts === 'string') {
    const ms = Date.parse(ts);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

/**
 * Employees who just submitted a new completion photo.
 */
function newCompletionSubmissions(beforeData, afterData) {
  const before = beforeData?.employeeCompletions || {};
  const after = afterData?.employeeCompletions || {};
  const results = [];

  for (const employeeId of Object.keys(after)) {
    const afterCompletion = after[employeeId];
    const afterMs = completionTimestampMs(afterCompletion);
    if (!afterMs) continue;

    const beforeMs = completionTimestampMs(before[employeeId]);
    if (beforeMs == null || afterMs > beforeMs) {
      results.push({employeeId, completion: afterCompletion});
    }
  }

  return results;
}

function buildContent(employeeName, taskDescription) {
  const description = (taskDescription || '').trim();
  const truncated = description.length > 80
      ? `${description.slice(0, 77)}…`
      : description;
  const taskClause = truncated ? ` "${truncated}"` : '';
  return {
    title: 'Task completed',
    body: `${employeeName} finished${taskClause}. Tap to review.`,
  };
}

/**
 * Resolve display name for the completing employee.
 */
async function employeeDisplayName(managerId, employeeId) {
  const db = getFirestore();
  try {
    const empSnap = await db
        .collection('users')
        .doc(managerId)
        .collection('employees')
        .doc(employeeId)
        .get();
    if (empSnap.exists) {
      const emp = empSnap.data() || {};
      if (emp.name) return String(emp.name);
      if (emp.username) return String(emp.username);
    }
  } catch (_) {
    // fall through
  }
  try {
    const userSnap = await db.collection('users').doc(employeeId).get();
    if (userSnap.exists) {
      const user = userSnap.data() || {};
      if (user.username) return String(user.username);
    }
  } catch (_) {
    // fall through
  }
  return 'An employee';
}

/**
 * Supervisors assigned to this location (User.role === 'supervisor').
 */
async function supervisorsForLocation(managerId, locationId) {
  const db = getFirestore();
  const snap = await db
      .collection('users')
      .doc(managerId)
      .collection('locations')
      .doc(locationId)
      .collection('employees')
      .get();

  const supervisorIds = [];
  await Promise.all(snap.docs.map(async (doc) => {
    try {
      const userSnap = await db.collection('users').doc(doc.id).get();
      if (userSnap.exists && userSnap.data()?.role === 'supervisor') {
        supervisorIds.push(doc.id);
      }
    } catch (_) {
      // skip
    }
  }));
  return supervisorIds;
}

exports.onTaskCompleted = onDocumentWritten(
    {
      document: 'users/{managerId}/locations/{locationId}/tasks/{taskId}',
      region: 'us-central1',
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!afterData) return;

      const submissions = newCompletionSubmissions(beforeData, afterData);
      if (submissions.length === 0) return;

      const {managerId, locationId, taskId} = event.params;

      for (const {employeeId} of submissions) {
        const employeeName = await employeeDisplayName(managerId, employeeId);
        const {title, body} = buildContent(employeeName, afterData.description);

        const recipientIds = new Set([managerId]);
        const supervisors = await supervisorsForLocation(managerId, locationId);
        supervisors.forEach((id) => recipientIds.add(id));

        // Don't notify the employee who just completed their own task.
        recipientIds.delete(employeeId);

        for (const recipientId of recipientIds) {
          try {
            const result = await sendPushToUser({
              userId: recipientId,
              category: 'tasks',
              title,
              body,
              data: {
                subtype: 'completed',
                taskId,
                locationId,
                managerId,
                employeeId,
              },
            });
            if (result.skipped) {
              console.log(`📭 Task completed push to ${recipientId} skipped: ${result.skipped}`);
            } else {
              console.log(`📨 Task completed push → ${recipientId} (sent=${result.sent}, dead=${result.dead})`);
            }
          } catch (err) {
            console.error(`🔴 Task completed push failed for ${recipientId}:`, err);
          }
        }
      }
    },
);

module.exports.__test__ = {newCompletionSubmissions, completionTimestampMs, buildContent};
