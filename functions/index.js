const {onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');

initializeApp();

// Notification triggers. Each lives in `notifications/` so adding
// new ones doesn't bloat this entry file. Re-exported here under
// stable names so deployment manifests stay simple.
const {onTaskAssigned} = require('./notifications/onTaskAssigned');
const {onTaskReviewed} = require('./notifications/onTaskReviewed');
const {onTaskCompleted} = require('./notifications/onTaskCompleted');
const {onEmployeeProfileChanged} = require('./notifications/onEmployeeProfileChanged');
const {onRoleChanged} = require('./notifications/onRoleChanged');
const {scheduledFinanceAlerts} = require('./notifications/scheduledFinanceAlerts');
const {scheduledComplianceAlerts} = require('./notifications/scheduledComplianceAlerts');
const {scheduledDueDateReminders} = require('./notifications/scheduledDueDateReminders');

exports.onTaskAssigned = onTaskAssigned;
exports.onTaskReviewed = onTaskReviewed;
exports.onTaskCompleted = onTaskCompleted;
exports.onEmployeeProfileChanged = onEmployeeProfileChanged;
exports.onRoleChanged = onRoleChanged;
exports.scheduledFinanceAlerts = scheduledFinanceAlerts;
exports.scheduledComplianceAlerts = scheduledComplianceAlerts;
exports.scheduledDueDateReminders = scheduledDueDateReminders;

// Callable functions invoked directly from the iOS client.
const {sendAnnouncement} = require('./announcements/sendAnnouncement');
exports.sendAnnouncement = sendAnnouncement;

/**
 * Cloud Function to delete Firebase Auth user when User document is deleted
 * This is triggered when a User document is deleted from Firestore
 */
exports.deleteUserOnUserDocumentDelete = onDocumentDeleted(
    {
      document: 'users/{userId}',
      region: 'us-central1',
    },
    async (event) => {
      const userId = event.params.userId;
      
      console.log(`🟢 User document deleted: ${userId}, attempting to delete Auth account...`);
      
      try {
        // Delete the Firebase Auth user account
        await getAuth().deleteUser(userId);
        console.log(`✅ Successfully deleted Auth account for user: ${userId}`);
      } catch (error) {
        // If user doesn't exist in Auth (already deleted or never existed), that's okay
        if (error.code === 'auth/user-not-found') {
          console.log(`⚠️ Auth user ${userId} not found (may have been already deleted)`);
          return;
        }
        
        // Log other errors but don't throw (to prevent retries)
        console.error(`🔴 Error deleting Auth account for user ${userId}:`, error);
      }
    }
);

