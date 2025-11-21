# Manager Login Setup Guide

## Overview

The Oplix app uses Firebase Authentication for manager logins. **There are no default credentials** - you need to create a manager account in Firebase.

## How Manager Login Works

1. Manager selects "Manager" on the role selection screen
2. Enters **email** and **password** (full email address, not username)
3. App authenticates with Firebase Auth
4. App fetches user data from Firestore to verify role is "manager"

## Creating Your First Manager Account

### Step 1: Create User in Firebase Authentication

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **oplix-3183d**
3. Navigate to **Authentication** → **Users**
4. Click **Add user**
5. Enter:
   - **Email**: Your manager email (e.g., `manager@oplix.com` or `admin@yourcompany.com`)
   - **Password**: Choose a secure password
6. Click **Add user**
7. **Copy the User UID** (you'll need this for Step 2)

### Step 2: Create User Document in Firestore

1. In Firebase Console, go to **Firestore Database**
2. Click on the **users** collection (or create it if it doesn't exist)
3. Click **Add document**
4. Set the **Document ID** to the **User UID** from Step 1
5. Add these fields:

   | Field | Type | Value |
   |-------|------|-------|
   | `id` | string | (same as Document ID - the User UID) |
   | `username` | string | `admin` (or your preferred username) |
   | `role` | string | `manager` |
   | `locationId` | null | (leave empty or set to `null`) |
   | `createdAt` | timestamp | (current timestamp) |

6. Click **Save**

### Example Firestore Document

```json
{
  "id": "abc123xyz789",
  "username": "admin",
  "role": "manager",
  "locationId": null,
  "createdAt": "2025-11-17T21:00:00Z"
}
```

## Login Credentials

After setup, use these credentials in the app:

- **Email**: The email you used in Firebase Authentication (e.g., `manager@oplix.com`)
- **Password**: The password you set in Firebase Authentication

## Quick Test Setup

For testing purposes, you can create a test manager:

1. **Firebase Authentication**:
   - Email: `test@oplix.com`
   - Password: `test123456` (or any password you choose)

2. **Firestore Document** (in `users` collection):
   - Document ID: (User UID from Authentication)
   - Fields:
     ```json
     {
       "id": "<UID>",
       "username": "testmanager",
       "role": "manager",
       "locationId": null,
       "createdAt": "<timestamp>"
     }
     ```

## Troubleshooting

### "User not found" or "Invalid credentials"
- Verify the email/password in Firebase Authentication → Users
- Make sure Email/Password authentication is enabled in Firebase

### "Access denied" or "Not a manager"
- Check that the Firestore document exists in the `users` collection
- Verify the `role` field is set to `"manager"` (lowercase)
- Ensure the document ID matches the User UID from Authentication

### Can't see manager dashboard
- Verify the user document has `"role": "manager"` (exact string, lowercase)
- Check that `locationId` is `null` or empty
- Ensure the app can read from Firestore (check security rules)

## Security Notes

- Managers have full access to all locations and data
- Use strong passwords for manager accounts
- Consider implementing additional security measures for production
- Review Firestore security rules to ensure proper access control

## Next Steps

After creating your manager account:
1. Open the Oplix app
2. Select "Manager" on the role selection screen
3. Enter your email and password
4. You should see the Manager Dashboard with all locations

