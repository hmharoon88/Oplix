/**
 * Cloud Function: notify a user when their role changes
 * (employee → supervisor or supervisor → employee).
 *
 * Trigger: user doc:
 *     users/{userId}
 *
 * Why a separate trigger from `onEmployeeProfileChanged`:
 *   - Role lives on the User doc, not the Employee doc, so this is
 *     a different document path entirely.
 *   - Role transitions also happen for the manager themselves in
 *     theory (rare but possible if we ever support multiple admins);
 *     scoping by document path is the cleanest way to keep concerns
 *     separated.
 *
 * Loop safety: this function is the only one that touches `lastPushAt`
 * indirectly (via `sendPushToUser`). The diff below early-exits on
 * any write that doesn't change `role`, so the `lastPushAt` write
 * never triggers a recursive notification. The same guard protects
 * us from `notificationPrefs` toggles, FCM token registrations
 * happening in subcollections (which don't fire user-doc triggers
 * anyway), and `organizationName` edits.
 */

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {sendPushToUser} = require('./sendPush');

const KNOWN_ROLES = new Set(['manager', 'employee', 'supervisor']);

function buildContent(beforeRole, afterRole) {
  // Promotions and demotions get distinct copy so the push reads
  // naturally without further branching.
  if (beforeRole !== 'supervisor' && afterRole === 'supervisor') {
    return {
      title: 'You were promoted to Supervisor',
      body: 'You now have supervisor access to your assigned locations.',
      subtype: 'promoted_supervisor',
    };
  }
  if (beforeRole === 'supervisor' && afterRole === 'employee') {
    return {
      title: 'Your role was updated',
      body: 'Your supervisor permissions were removed.',
      subtype: 'demoted_employee',
    };
  }
  // Generic fallback for any other transition (defensive — covers
  // future roles or oddball admin edits without crashing).
  return {
    title: 'Your role was updated',
    body: `Your role is now ${afterRole}.`,
    subtype: 'role_changed',
  };
}

exports.onRoleChanged = onDocumentWritten(
    {
      document: 'users/{userId}',
      region: 'us-central1',
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();

      // Creation or deletion — neither is a role *transition*.
      if (!beforeData || !afterData) return;

      const beforeRole = beforeData.role;
      const afterRole = afterData.role;

      if (beforeRole === afterRole) return; // unrelated edit
      if (!KNOWN_ROLES.has(afterRole)) return; // ignore unexpected values

      const {userId} = event.params;
      const {title, body, subtype} = buildContent(beforeRole, afterRole);

      try {
        const result = await sendPushToUser({
          userId,
          category: 'assignment',
          title,
          body,
          data: {
            subtype,
            beforeRole: beforeRole || '',
            afterRole,
          },
        });
        if (result.skipped) {
          console.log(`📭 Role change push to ${userId} skipped: ${result.skipped}`);
        } else {
          console.log(`📨 Role change push → ${userId} (sent=${result.sent}, dead=${result.dead})`);
        }
      } catch (err) {
        console.error(`🔴 Role change push failed for ${userId}:`, err);
      }
    },
);

module.exports.__test__ = {buildContent};
