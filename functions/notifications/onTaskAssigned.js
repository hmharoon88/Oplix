/**
 * Cloud Function: notify employees when they're assigned to a task.
 *
 * Trigger: any write to a location-level task doc:
 *     users/{managerId}/locations/{locationId}/tasks/{taskId}
 *
 * Why location-level (not the manager-level mirror at
 * users/{userId}/tasks/{taskId}):
 *   - Location-level docs are the source of truth that employees
 *     read via `observeTasks(userId:locationId:)` — they always
 *     have the up-to-date `assignedEmployeeIds` value.
 *   - Listening on manager-level would need extra logic to figure
 *     out which location the task is being mirrored to, since one
 *     manager-level task can fan out to multiple locations.
 *
 * The function diffs `assignedEmployeeIds` between before and after
 * and only notifies the **newly added** employees. That way:
 *   - Creating a task with 3 assignees → 3 pushes
 *   - Editing other fields without changing assignees → 0 pushes
 *   - Adding a 4th assignee later → 1 push
 *
 * `_id` and `crossLocationGroupId` are preserved unchanged on the
 * task doc — the function reads, doesn't write back.
 */

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {sendPushToUser} = require('./sendPush');

/**
 * Build the human-facing title/body for the push. Kept in one place
 * so the wording can be tweaked without hunting through the trigger
 * logic.
 */
function buildContent(taskDescription) {
  const description = (taskDescription || '').trim();
  const truncated = description.length > 140
      ? `${description.slice(0, 137)}…`
      : description;
  return {
    title: 'New task assigned',
    body: truncated.length > 0 ? truncated : 'You have a new task to complete.',
  };
}

/**
 * Compute newly-added assignees: present in `after` but absent from `before`.
 */
function newlyAddedAssignees(before, after) {
  const beforeSet = new Set(Array.isArray(before) ? before : []);
  const afterArr = Array.isArray(after) ? after : [];
  return afterArr.filter((id) => !beforeSet.has(id));
}

exports.onTaskAssigned = onDocumentWritten(
    {
      document: 'users/{managerId}/locations/{locationId}/tasks/{taskId}',
      region: 'us-central1',
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();

      // Doc deletion — nothing to notify about. The "task removed"
      // notification (if/when we add it) will live in its own
      // function so deletion logic stays separate.
      if (!afterData) return;

      const beforeAssignees = beforeData?.assignedEmployeeIds || [];
      const afterAssignees = afterData.assignedEmployeeIds || [];
      const added = newlyAddedAssignees(beforeAssignees, afterAssignees);
      if (added.length === 0) return;

      const {managerId, locationId, taskId} = event.params;
      const {title, body} = buildContent(afterData.description);

      // Fan out one push per newly-added assignee. Sequential rather
      // than parallel so a slow recipient (token cleanup, etc.)
      // doesn't make the others wait — simple await loop is fine at
      // these volumes (typically 1–5 employees).
      for (const employeeId of added) {
        try {
          const result = await sendPushToUser({
            userId: employeeId,
            category: 'tasks',
            title,
            body,
            data: {
              subtype: 'assigned',
              taskId,
              locationId,
              managerId,
            },
          });
          if (result.skipped) {
            console.log(`📭 Task assigned to ${employeeId} skipped: ${result.skipped}`);
          } else {
            console.log(`📨 Task assigned push → ${employeeId} (sent=${result.sent}, dead=${result.dead})`);
          }
        } catch (err) {
          // Never throw out of a Firestore trigger — a single failure
          // shouldn't take the whole batch down or trigger a retry
          // (which could re-deliver to the others).
          console.error(`🔴 Task assigned push failed for ${employeeId}:`, err);
        }
      }
    },
);
