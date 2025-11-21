# How to Log In to Oplix

## Quick Start Guide

### Step 1: Create a Manager Account (First Time Only)

If you haven't created a manager account yet, you need to set one up in Firebase:

#### A. Create User in Firebase Authentication

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **oplix-3183d**
3. Click **Authentication** in the left menu
4. Click **Users** tab
5. Click **Add user** button
6. Enter:
   - **Email**: `manager@oplix.com` (or any email you prefer)
   - **Password**: Choose a password (e.g., `manager123`)
7. Click **Add user**
8. **IMPORTANT**: Copy the **User UID** (you'll need this next)

#### B. Create User Document in Firestore

1. In Firebase Console, click **Firestore Database** in the left menu
2. Click on the **users** collection (or create it if it doesn't exist)
3. Click **Add document**
4. Set the **Document ID** to the **User UID** you copied from step A
5. Add these fields by clicking **Add field**:

   | Field Name | Type | Value |
   |------------|------|-------|
   | `id` | string | (paste the User UID again) |
   | `username` | string | `admin` |
   | `role` | string | `manager` |
   | `locationId` | null | (leave empty or select "null") |
   | `createdAt` | timestamp | (click and select current date/time) |

6. Click **Save**

### Step 2: Deploy Firestore Rules (If Not Done Yet)

1. In Firebase Console → **Firestore Database** → **Rules** tab
2. Copy the contents of `firestore.rules` file from your project
3. Paste into the Rules editor
4. Click **Publish**

### Step 3: Log In to the App

1. **Open the Oplix app** on your device/simulator
2. You'll see the **Role Selection** screen
3. Tap **"Manager"** button
4. Enter your credentials:
   - **Email**: The email you used in Firebase Authentication (e.g., `manager@oplix.com`)
   - **Password**: The password you set in Firebase Authentication
5. Tap **"Sign In"**
6. You should now see the **Manager Dashboard**

## Example Login Credentials

If you created a test account:
- **Email**: `manager@oplix.com`
- **Password**: `manager123` (or whatever you set)

## Troubleshooting

### "Sign in failed" Error

**Check:**
1. ✅ User exists in Firebase Authentication → Users
2. ✅ User document exists in Firestore → users collection
3. ✅ Document ID matches User UID from Authentication
4. ✅ `role` field is exactly `"manager"` (lowercase)
5. ✅ Firestore rules are deployed

### "Permission denied" Error

**Fix:**
1. Make sure you deployed the updated `firestore.rules` to Firebase
2. The rules should allow users to read their own document

### Can't See Manager Dashboard

**Check:**
1. The `role` field in Firestore must be exactly `"manager"` (lowercase)
2. The document structure is correct (see Step 1B above)

## Quick Checklist

Before logging in, verify:

- [ ] User created in Firebase Authentication
- [ ] User document created in Firestore `users` collection
- [ ] Document ID = User UID from Authentication
- [ ] `role` field = `"manager"` (lowercase)
- [ ] Firestore rules deployed
- [ ] App is running and connected to Firebase

## Need Help?

If you're still having issues:
1. Check the error message shown in the app
2. Verify all steps in the checklist above
3. See `TROUBLESHOOT_MANAGER_LOGIN.md` for detailed troubleshooting

