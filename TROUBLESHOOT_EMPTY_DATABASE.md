# Troubleshooting: Empty Database

## Why You Might Not See Data

There are several reasons why you might not see data in Firebase. Let's check them one by one.

## Step 1: Check if Firestore Database Exists

### ⚠️ **Most Common Issue: Database Not Created**

Earlier you saw this error:
```
The database (default) does not exist for project oplix-3183d
```

**Solution:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **oplix-3183d**
3. Click **Firestore Database** in left sidebar
4. If you see "Create database" button → **Click it!**
5. Choose **Production mode** (we'll use security rules)
6. Select a location (choose closest to you)
7. Click **Enable**

**After creating database:**
- Copy your `firestore.rules` to Firebase Console → Rules tab
- Click **Publish**

## Step 2: Have You Created Any Data in the App?

### Check if you've actually used the app:

1. **Did you sign up as a manager?**
   - If yes → Check `users` collection in Firestore
   - You should see your user document

2. **Did you create a location?**
   - If yes → Check `locations` collection
   - You should see location documents

3. **Did you create an employee?**
   - If yes → Check `employees` collection
   - You should see employee documents

### If you haven't created data yet:
- **That's why the database is empty!**
- Create a location in the app first
- Then check Firebase Console

## Step 3: Check Where to Look in Firebase Console

### Correct Path:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **oplix-3183d**
3. Click **Firestore Database** (not Realtime Database!)
4. Click **Data** tab (not Rules tab)
5. You should see collections listed:
   - `users`
   - `locations`
   - `employees`
   - `tasks`
   - `shifts`
   - `lotteryForms`

### Common Mistake:
- ❌ Looking at **Realtime Database** instead of **Firestore Database**
- ✅ Make sure you're in **Firestore Database**

## Step 4: Check for Errors in the App

### Check Xcode Console for Errors:

When you create a location, do you see:
- ✅ Success message?
- ❌ Error message?

### Common Errors:

**Error 1: "Permission denied"**
- **Cause:** Security rules blocking writes
- **Fix:** Publish updated `firestore.rules` to Firebase Console

**Error 2: "Database does not exist"**
- **Cause:** Firestore database not created
- **Fix:** Create database in Firebase Console (Step 1)

**Error 3: "Network error"**
- **Cause:** No internet connection
- **Fix:** Check internet connection

## Step 5: Verify App is Connected to Firebase

### Check GoogleService-Info.plist:
1. Open Xcode
2. Check if `GoogleService-Info.plist` is in your project
3. Make sure it's added to the **Oplix** target
4. Check **Build Phases** → **Copy Bundle Resources**
5. `GoogleService-Info.plist` should be listed

### Verify Bundle ID:
- Open `GoogleService-Info.plist`
- Check `BUNDLE_ID` matches your app's bundle ID
- In Xcode: Project Settings → General → Bundle Identifier

## Step 6: Test Data Creation

### Quick Test:
1. **Open the app**
2. **Sign up as a manager** (if not already)
3. **Create a location:**
   - Tap "Add Location" button
   - Enter name: "Test Store"
   - Enter address: "123 Test St"
   - Tap "Save"
4. **Check Firebase Console:**
   - Go to Firestore Database → Data tab
   - Look for `locations` collection
   - You should see "Test Store"

### If location doesn't appear:
- Check Xcode console for errors
- Verify internet connection
- Check if Firestore database exists
- Verify security rules are published

## Step 7: Check Security Rules

### If rules are too restrictive:
- They might be blocking writes
- Make sure you published the updated rules
- Check Rules tab in Firebase Console for errors

### Test Rules:
1. Go to Firebase Console → Firestore Database → Rules
2. Check if rules are published
3. Look for syntax errors (highlighted in red)

## Step 8: Check Authentication

### Make sure you're signed in:
- App needs authenticated user to save data
- Check if you're logged in as manager
- If not logged in → Sign up or sign in first

## Quick Checklist

Before checking database, verify:
- ✅ Firestore database created in Firebase Console
- ✅ Security rules published to Firebase Console
- ✅ `GoogleService-Info.plist` added to Xcode project
- ✅ App bundle ID matches `GoogleService-Info.plist`
- ✅ You're signed in as manager in the app
- ✅ You've actually created data (location, employee, etc.)
- ✅ Internet connection is working
- ✅ Looking at **Firestore Database** (not Realtime Database)

## Still Empty?

### Debug Steps:
1. **Add debug logging:**
   - Check Xcode console when creating location
   - Look for error messages

2. **Test with Firebase Console directly:**
   - Try creating a document manually in Firebase Console
   - If that works → Issue is with app
   - If that fails → Issue is with database setup

3. **Check Firebase project:**
   - Verify you're looking at correct project: **oplix-3183d**
   - Check if billing is enabled (if required)

## Most Likely Issues (in order):

1. **Firestore database not created** (most common)
2. **Haven't created any data in app yet**
3. **Looking at wrong database** (Realtime vs Firestore)
4. **Security rules blocking writes**
5. **Not signed in** in the app

## Next Steps

1. **First:** Create Firestore database if it doesn't exist
2. **Second:** Sign up as manager in the app
3. **Third:** Create a location in the app
4. **Fourth:** Check Firebase Console → Firestore Database → Data tab
5. **Fifth:** You should see your data!

