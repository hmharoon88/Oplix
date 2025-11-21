# Verify and Publish Your Security Rules

## ✅ Your Rules Look Correct!

The rules you pasted are correct and should work. Now you need to **publish them** to Firebase Console.

## Step-by-Step: Publish Rules

### Step 1: Open Firebase Console Rules
1. Go to: https://console.firebase.google.com/project/oplix-3183d/firestore/rules
2. Or: Firebase Console → Firestore Database → **Rules** tab

### Step 2: Copy Your Rules
**Option A: Terminal (macOS)**
```bash
cat firestore.rules | pbcopy
```

**Option B: Manual**
1. Open `firestore.rules` file in your project
2. Select all (Cmd+A)
3. Copy (Cmd+C)

### Step 3: Paste into Firebase Console
1. In Firebase Console Rules tab
2. Select all existing rules (Cmd+A)
3. Delete them (Backspace)
4. Paste your rules (Cmd+V)

### Step 4: Check for Errors
1. Look for red error highlights
2. If you see errors, check:
   - Missing closing braces `}`
   - Syntax errors
   - Typos

### Step 5: Publish
1. Click **"Publish"** button (usually at top right)
2. Wait for "Rules published successfully" message
3. Rules take effect immediately!

## Important: First Manager Sign-Up

When a manager signs up for the first time:

1. **App creates Firebase Auth user** ✅
2. **App creates user document in Firestore** ✅
   - This should work because rule allows: `request.auth.uid == userId`
3. **Manager can then create locations** ✅
   - This requires `isManager()` which checks if user document exists

**Potential Issue:** If manager tries to create location immediately after sign-up, there might be a tiny delay. But the async code should handle this.

## Testing After Publishing Rules

### Test 1: Sign Up as Manager
1. Open your app
2. Tap "Manager" → "Sign Up"
3. Enter email, password, username
4. Tap "Sign Up"
5. **Check Xcode console** for errors
6. **Check Firebase Console → Firestore → Data tab**
   - Should see `users` collection
   - Should see your user document with `role: "manager"`

### Test 2: Create Location
1. After signing up, you should see "Locations" screen
2. Tap "+" button (Add Location)
3. Enter name: "Test Store"
4. Enter address: "123 Test St"
5. Tap "Save"
6. **Check Xcode console** for errors
7. **Check Firebase Console → Firestore → Data tab**
   - Should see `locations` collection
   - Should see your "Test Store" document

## Common Errors After Publishing

### Error: "Permission denied"
**Cause:** Rules might be too restrictive or have syntax error
**Fix:** 
1. Check Rules tab for syntax errors
2. Verify you're signed in as manager
3. Check if user document exists in `users` collection

### Error: "Missing or insufficient permissions"
**Cause:** User document doesn't exist or role is wrong
**Fix:**
1. Check Firebase Console → Firestore → Data → `users` collection
2. Verify your user document exists
3. Verify `role` field is set to `"manager"` (string, not enum)

### Error: "isManager() returns false"
**Cause:** User document doesn't exist or role field is wrong
**Fix:**
1. Check `users` collection in Firestore
2. Make sure document ID matches Firebase Auth UID
3. Make sure `role` field is exactly `"manager"` (lowercase string)

## Quick Debug: Check User Document

After signing up, check Firebase Console:

1. Go to Firestore Database → Data tab
2. Click on `users` collection
3. Find your user document (ID = Firebase Auth UID)
4. Verify fields:
   - `id`: Should match document ID
   - `username`: Your username
   - `role`: Should be `"manager"` (string)
   - `locationId`: Should be `null`
   - `createdAt`: Should be a timestamp

**If user document is missing:**
- Sign-up failed
- Check Xcode console for errors
- Try signing up again

## If Rules Still Don't Work

### Temporary Test: Use Simple Rules

To verify it's a rules issue, temporarily use these simple rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**Steps:**
1. Paste these simple rules
2. Publish
3. Try creating a location
4. If it works → Your original rules have an issue
5. If it doesn't work → Issue is authentication or connection

**After testing:**
- Replace with your secure rules
- Publish again

## Summary

**Your rules are correct!** Now:
1. ✅ Copy your `firestore.rules` file
2. ✅ Paste into Firebase Console → Rules tab
3. ✅ Click "Publish"
4. ✅ Test signing up as manager
5. ✅ Test creating a location
6. ✅ Check Firebase Console → Data tab to see your data!

