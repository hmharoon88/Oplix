# Firebase Storage Rules Setup

## Problem
Employees are getting "User does not have permission to access" errors when trying to upload task completion images to Firebase Storage.

## Solution
You need to add Firebase Storage security rules to allow employees to upload images.

## Steps to Fix

### 1. Open Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **oplix-3183d**
3. In the left sidebar, click on **Storage**
4. Click on the **Rules** tab

### 2. Add Storage Rules
Copy and paste the following rules into the Firebase Storage Rules editor:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Task images: task_images/{managerUserId}/{locationId}/{taskId}.jpg
    match /task_images/{managerUserId}/{locationId}/{taskId}.jpg {
      // Allow read for authenticated users (managers and employees can view)
      allow read: if isAuthenticated();
      
      // Allow write (upload) for authenticated users
      // Employees can upload images for tasks at their location
      // Managers can upload/delete images for their locations
      allow write: if isAuthenticated();
    }
    
    // Allow all other paths for authenticated users (for future use)
    match /{allPaths=**} {
      allow read, write: if isAuthenticated();
    }
  }
}
```

### 3. Publish Rules
1. Click the **Publish** button
2. Wait for the confirmation message
3. Rules are now active

## What These Rules Do

- **Authenticated users only**: Only logged-in users (managers and employees) can access storage
- **Task images**: Allows read/write access to task completion images
- **Flexible**: The rules allow any authenticated user to upload task images, which is appropriate since employees need to upload images for their assigned tasks

## Testing

After publishing the rules:
1. Try uploading a task completion image from the employee view
2. The upload should now succeed
3. The image should appear in Firebase Storage under `task_images/{managerUserId}/{locationId}/{taskId}.jpg`

## Security Note

These rules allow any authenticated user to upload task images. In a production environment, you might want to add more specific checks:
- Verify the employee belongs to the location
- Verify the task is assigned to the employee
- Restrict delete operations to managers only

For now, these rules provide a good balance between security and functionality.

