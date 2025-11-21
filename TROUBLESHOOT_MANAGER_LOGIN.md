# Troubleshooting Manager Login Issues

## Common Issues and Solutions

### Issue 1: "Sign in failed" or "Failed to load user"

**Root Cause**: The user document doesn't exist in Firestore, or Firestore security rules are blocking access.

**Solution**:
1. **Check if user exists in Firebase Authentication**:
   - Go to Firebase Console → Authentication → Users
   - Verify the email you're using exists

2. **Check if user document exists in Firestore**:
   - Go to Firebase Console → Firestore Database
   - Check the `users` collection
   - Verify there's a document with the User UID as the Document ID
   - The document must have these fields:
     - `id`: (string, same as Document ID)
     - `username`: (string)
     - `role`: (string, must be exactly `"manager"`)
     - `locationId`: (null or empty)
     - `createdAt`: (timestamp)

3. **Check Firestore Security Rules**:
   - Go to Firebase Console → Firestore Database → Rules
   - Make sure the rules allow users to read their own document
   - The updated rules should include: `allow read: if isAuthenticated() && (request.auth.uid == userId || isManager());`

### Issue 2: "Permission denied" error

**Root Cause**: Firestore security rules are blocking the read operation.

**Solution**:
1. **Update Firestore Rules** (see `firestore.rules` file):
   - Users must be able to read their own document for initial sign-in
   - The rules have been updated to fix a circular dependency issue

2. **Deploy the updated rules**:
   - Copy the contents of `firestore.rules`
   - Go to Firebase Console → Firestore Database → Rules
   - Paste and click "Publish"

### Issue 3: User signs in but doesn't see manager dashboard

**Root Cause**: The user document exists but the `role` field is incorrect.

**Solution**:
1. Check the `role` field in Firestore:
   - Must be exactly `"manager"` (lowercase, with quotes in JSON)
   - Not `"Manager"`, `"MANAGER"`, or `manager` (without quotes)

2. Verify the document structure:
   ```json
   {
     "id": "<User UID>",
     "username": "admin",
     "role": "manager",
     "locationId": null,
     "createdAt": "<timestamp>"
   }
   ```

### Issue 4: "User not found" in Firestore

**Root Cause**: User exists in Authentication but not in Firestore.

**Solution**:
1. Create the user document manually:
   - Get the User UID from Firebase Authentication → Users
   - Go to Firestore Database → `users` collection
   - Create a new document with the UID as Document ID
   - Add the required fields (see Issue 1, step 2)

### Issue 5: Circular dependency in Firestore rules

**Root Cause**: The security rules try to check if user is manager before allowing read, but need to read the document to check the role.

**Solution**:
The rules have been updated to:
- Allow users to read their own document first (needed for sign-in)
- Then check manager status for reading other documents
- Handle null user documents gracefully

## Step-by-Step Fix

1. **Verify Firebase Authentication**:
   ```
   ✅ User exists in Authentication
   ✅ Email/Password authentication is enabled
   ✅ User has correct email and password
   ```

2. **Create/Verify Firestore User Document**:
   ```
   ✅ Document exists in `users` collection
   ✅ Document ID = User UID from Authentication
   ✅ Fields: id, username, role="manager", locationId=null, createdAt
   ```

3. **Update Firestore Security Rules**:
   ```
   ✅ Rules allow users to read their own document
   ✅ Rules handle null user documents
   ✅ Rules published to Firebase
   ```

4. **Test Sign-In**:
   ```
   ✅ Open app
   ✅ Select "Manager"
   ✅ Enter email and password
   ✅ Should see Manager Dashboard
   ```

## Quick Test

To verify everything is set up correctly:

1. **Check Authentication**:
   ```bash
   # In Firebase Console
   Authentication → Users → [Your email should be listed]
   ```

2. **Check Firestore**:
   ```bash
   # In Firebase Console
   Firestore Database → users → [Document with your UID]
   # Verify role field = "manager"
   ```

3. **Check Rules**:
   ```bash
   # In Firebase Console
   Firestore Database → Rules
   # Should allow: allow read: if isAuthenticated() && (request.auth.uid == userId || isManager());
   ```

## Still Having Issues?

If you're still unable to sign in:

1. **Check the error message** in the app - it will show the specific Firebase error
2. **Check Xcode console** for detailed error logs
3. **Verify GoogleService-Info.plist** is included in the app bundle
4. **Check Firebase project** is correctly configured
5. **Ensure Email/Password authentication** is enabled in Firebase Console

## Error Messages Reference

- `"The email address is badly formatted"` → Check email format
- `"There is no user record corresponding to this identifier"` → User doesn't exist in Authentication
- `"The password is invalid"` → Wrong password
- `"Permission denied"` → Firestore rules blocking access
- `"Document does not exist"` → User document missing in Firestore
- `"Failed to load user"` → Cannot read user document from Firestore

