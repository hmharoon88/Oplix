const {onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');

initializeApp();

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

