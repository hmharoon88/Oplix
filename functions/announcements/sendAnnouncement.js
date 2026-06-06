/**
 * sendAnnouncement — manager-initiated broadcast push to employees.
 *
 * Invoked by the iOS app via Firebase Callable Functions. The caller
 * must be authenticated and have role `manager` (or `supervisor` for
 * the location they manage). The function resolves the target list,
 * then fans out via the shared sendPushToUser helper so the recipient's
 * own NotificationPrefs (categories + quiet hours) still gate delivery.
 *
 * Request payload:
 *   {
 *     title: string,
 *     body: string,
 *     locationId?: string   // when present, scope to one location;
 *                            // when absent, broadcast to all employees
 *                            // owned by the caller (manager).
 *   }
 *
 * Response payload:
 *   { delivered: number, skipped: number, recipients: number }
 */

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore} = require('firebase-admin/firestore');
const {sendPushToUser} = require('../notifications/sendPush');

const ANNOUNCEMENT_CATEGORY = 'assignment';
const MAX_BROADCAST_RECIPIENTS = 500;

exports.sendAnnouncement = onCall(
    {region: 'us-central1'},
    async (req) => {
      // ---- AuthN ----
      if (!req.auth) {
        throw new HttpsError('unauthenticated', 'Sign-in required.');
      }
      const callerUid = req.auth.uid;

      // ---- Input validation ----
      const data = req.data || {};
      const title = String(data.title || '').trim();
      const body = String(data.body || '').trim();
      const locationId = data.locationId
          ? String(data.locationId)
          : null;
      if (title.length === 0 || title.length > 80) {
        throw new HttpsError('invalid-argument', 'Title is required and must be 1–80 chars.');
      }
      if (body.length === 0 || body.length > 500) {
        throw new HttpsError('invalid-argument', 'Body is required and must be 1–500 chars.');
      }

      const db = getFirestore();

      // ---- AuthZ: caller must be manager (or a supervisor on the
      // target location). Anonymous employees can NOT broadcast.
      const callerSnap = await db.doc(`users/${callerUid}`).get();
      if (!callerSnap.exists) {
        throw new HttpsError('permission-denied', 'Caller has no user profile.');
      }
      const caller = callerSnap.data() || {};
      const role = caller.role;

      const isManager = role === 'manager';
      const isSupervisorForLocation = role === 'supervisor' && locationId
          ? (Array.isArray(caller.assignedLocationIds) &&
              caller.assignedLocationIds.includes(locationId))
          : false;

      if (!isManager && !isSupervisorForLocation) {
        throw new HttpsError('permission-denied',
            'Only the manager (or a supervisor on this location) can broadcast.');
      }

      // The "owning" manager id for the cohort the message goes to.
      // For supervisor calls, that's whoever owns their user doc.
      const ownerId = isManager ? callerUid : (caller.managerUserId || callerUid);

      // ---- Resolve recipients ----
      // Employees collection layout (per the iOS app):
      //   users/{managerUserId}/employees/{employeeId}
      // Each employee doc has `locationId` (legacy) or `assignedLocationIds`
      // (the new multi-location field). We respect both.
      const employeesRef = db.collection('users').doc(ownerId).collection('employees');
      const allEmployeesSnap = await employeesRef.get();

      const recipientIds = new Set();
      allEmployeesSnap.forEach((doc) => {
        const emp = doc.data() || {};
        if (locationId) {
          const legacyMatch = emp.locationId === locationId;
          const newMatch = Array.isArray(emp.assignedLocationIds) &&
              emp.assignedLocationIds.includes(locationId);
          if (legacyMatch || newMatch) {
            recipientIds.add(doc.id);
          }
        } else {
          recipientIds.add(doc.id);
        }
      });

      if (recipientIds.size === 0) {
        return {delivered: 0, skipped: 0, recipients: 0};
      }
      if (recipientIds.size > MAX_BROADCAST_RECIPIENTS) {
        throw new HttpsError('resource-exhausted',
            `Broadcast exceeds ${MAX_BROADCAST_RECIPIENTS} recipients.`);
      }

      // ---- Persist for audit trail (so the manager can see history) ----
      // Stored under the owning manager's user doc for tenant isolation.
      const announcementRef = await db.collection('users').doc(ownerId)
          .collection('announcements').add({
            title,
            body,
            locationId: locationId || null,
            authorId: callerUid,
            recipientIds: Array.from(recipientIds),
            sentAt: new Date(),
          });

      // ---- Fan out pushes in parallel ----
      let delivered = 0;
      let skipped = 0;
      await Promise.all(Array.from(recipientIds).map(async (uid) => {
        try {
          const result = await sendPushToUser({
            userId: uid,
            category: ANNOUNCEMENT_CATEGORY,
            title,
            body,
            data: {
              type: 'announcement',
              announcementId: announcementRef.id,
              ...(locationId ? {locationId} : {}),
            },
          });
          if (result && result.sent > 0) {
            delivered += 1;
          } else {
            // Recipient is opted out, has no device tokens, or is in quiet hours.
            skipped += 1;
          }
        } catch (err) {
          console.error(`Announcement push failed for ${uid}`, err);
          skipped += 1;
        }
      }));

      return {delivered, skipped, recipients: recipientIds.size};
    }
);
