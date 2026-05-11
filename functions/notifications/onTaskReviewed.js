/**
 * Cloud Function: notify an employee when their task completion is
 * approved or disapproved by a manager / supervisor.
 *
 * Trigger: same task path as `onTaskAssigned`. Multiple Cloud Functions
 * can listen to the same Firestore document — Firebase fans out the
 * event independently, and each function early-exits when it doesn't
 * detect "its" change. So `onTaskAssigned` reacts to `assignedEmployeeIds`
 * diffs and we react to `employeeCompletions[*].isApproved` diffs.
 *
 * Approval transitions we care about:
 *
 *   undefined → true   (manager approved)         subtype: 'approved'
 *   undefined → false  (manager disapproved)      subtype: 'disapproved'
 *           true → false (changed mind, disapproved)
 *          false → true  (changed mind, approved)
 *
 * undefined→undefined and false→nothing-deleted aren't covered (they're
 * not real review events).
 */

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {sendPushToUser} = require('./sendPush');

/**
 * Pull a flat map of `{employeeId: isApproved}` for a side. Treats
 * "missing completion" identically to "isApproved=undefined" so the
 * diff below is symmetric on both sides.
 */
function approvalMap(taskData) {
  const completions = (taskData && taskData.employeeCompletions) || {};
  const out = {};
  for (const employeeId of Object.keys(completions)) {
    const completion = completions[employeeId] || {};
    out[employeeId] = typeof completion.isApproved === 'boolean'
        ? completion.isApproved
        : undefined;
  }
  return out;
}

/**
 * Compare before/after approval state per employee and yield the
 * transitions that warrant a notification. We only fire on
 * "undefined ↔ true|false" or "true ↔ false" — no-op rewrites of the
 * same state don't push.
 */
function reviewTransitions(beforeData, afterData) {
  const before = approvalMap(beforeData);
  const after = approvalMap(afterData);
  const transitions = [];
  for (const employeeId of Object.keys(after)) {
    const a = after[employeeId];
    const b = before[employeeId];
    if (a === b) continue; // unchanged
    if (a !== true && a !== false) continue; // only act when after is a definitive review

    transitions.push({
      employeeId,
      isApproved: a,
      disapprovalNote:
          a === false
              ? (afterData?.employeeCompletions?.[employeeId]?.disapprovalNote || '')
              : '',
    });
  }
  return transitions;
}

function buildContent(transition, taskDescription) {
  const description = (taskDescription || '').trim();
  const truncated = description.length > 100
      ? `${description.slice(0, 97)}…`
      : description;
  const taskClause = truncated ? ` "${truncated}"` : '';
  if (transition.isApproved === true) {
    return {
      title: 'Task approved',
      body: `Your work on${taskClause} was approved. Nice job.`,
    };
  }
  // Disapproved
  const note = (transition.disapprovalNote || '').trim();
  const noteSuffix = note ? ` — ${note}` : '';
  return {
    title: 'Task needs to be redone',
    body: `Your photo for${taskClause} was disapproved.${noteSuffix}`.trim(),
  };
}

exports.onTaskReviewed = onDocumentWritten(
    {
      document: 'users/{managerId}/locations/{locationId}/tasks/{taskId}',
      region: 'us-central1',
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!afterData) return; // task deleted — nothing to review

      const transitions = reviewTransitions(beforeData, afterData);
      if (transitions.length === 0) return;

      const {managerId, locationId, taskId} = event.params;

      for (const transition of transitions) {
        const {title, body} = buildContent(transition, afterData.description);
        try {
          const result = await sendPushToUser({
            userId: transition.employeeId,
            category: 'tasks',
            title,
            body,
            data: {
              subtype: transition.isApproved ? 'approved' : 'disapproved',
              taskId,
              locationId,
              managerId,
            },
          });
          if (result.skipped) {
            console.log(`📭 Task review push to ${transition.employeeId} skipped: ${result.skipped}`);
          } else {
            console.log(`📨 Task review push → ${transition.employeeId} (sent=${result.sent}, dead=${result.dead})`);
          }
        } catch (err) {
          // Trigger isolation: a single recipient failure shouldn't
          // tank the rest or trigger the function's automatic retry
          // (which would re-deliver to everyone).
          console.error(`🔴 Task review push failed for ${transition.employeeId}:`, err);
        }
      }
    },
);

module.exports.__test__ = {reviewTransitions, approvalMap, buildContent};
