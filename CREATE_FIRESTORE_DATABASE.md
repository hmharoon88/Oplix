# Create Firestore Database - Step by Step

## ✅ The Error Means: Database Doesn't Exist Yet

The error you're seeing means the Firestore database hasn't been created in your Firebase project. Let's create it now!

## Step-by-Step Instructions

### Step 1: Open Firebase Console
1. Go to: https://console.firebase.google.com/project/oplix-3183d/firestore
2. Or go to: https://console.firebase.google.com/
3. Select your project: **oplix-3183d**

### Step 2: Navigate to Firestore
1. In the left sidebar, click **Firestore Database**
2. If you see "Create database" button → Click it!
3. If you see "Get started" → Click it!

### Step 3: Create Database
1. You'll see two options:
   - **Production mode** ← Choose this one!
   - Test mode
2. Click **Production mode**
3. Click **Next**

### Step 4: Choose Location
1. Select a location closest to you:
   - **us-central** (Iowa, USA) - Good for US
   - **europe-west** (Belgium) - Good for Europe
   - **asia-southeast1** (Singapore) - Good for Asia
2. Click **Enable**

### Step 5: Wait for Creation
- Database creation takes 30-60 seconds
- You'll see a progress indicator
- Wait until it says "Database created successfully"

### Step 6: Publish Security Rules
1. After database is created, click the **Rules** tab
2. You'll see default rules (very permissive)
3. **Replace them** with your secure rules:
   - Open `firestore.rules` file from your project
   - Copy ALL the content (Cmd+A, Cmd+C)
   - Paste into Firebase Console Rules editor (Cmd+V)
   - Click **Publish**

### Step 7: Verify
1. Click the **Data** tab
2. You should see an empty database (no collections yet)
3. This is normal! Collections are created when you add data in the app

## After Creating Database

### Test in Your App:
1. **Restart your app** (close and reopen)
2. **Sign up as a manager** (or sign in)
3. **Create a location:**
   - Tap "Add Location"
   - Enter name: "Test Store"
   - Enter address: "123 Test St"
   - Tap "Save"
4. **Check Firebase Console:**
   - Go to Firestore Database → Data tab
   - You should now see:
     - `locations` collection
     - Your "Test Store" document inside!

## Quick Link

**Direct link to create database:**
https://console.firebase.google.com/project/oplix-3183d/firestore

## What You'll See

### Before Creating Database:
- Error in console: "The database (default) does not exist"
- Empty database view
- "Create database" button

### After Creating Database:
- No more errors in console
- Database view shows "No data" (normal - collections created when you add data)
- Ready to accept data from your app!

## Important Notes

⚠️ **Choose Production Mode:**
- Production mode uses security rules (which we've set up)
- Test mode allows all reads/writes (not secure)

⚠️ **Location Matters:**
- Choose closest to your users
- Can't change later (easily)
- Affects latency

⚠️ **Security Rules:**
- Must publish your `firestore.rules` after creating database
- Without rules, database might be too permissive or too restrictive

## Troubleshooting

### If "Create database" button doesn't appear:
1. Make sure you're in the correct project: **oplix-3183d**
2. Check if database already exists (look in Data tab)
3. Try refreshing the page

### If creation fails:
1. Check if billing is enabled (Firestore requires billing for some regions)
2. Try a different location
3. Check Firebase Console for error messages

### After creating, still see errors:
1. **Restart your app** (close completely and reopen)
2. Make sure you're signed in as manager
3. Check Xcode console for new errors

## Summary

**The error means:** Database doesn't exist yet
**The solution:** Create it in Firebase Console
**Time needed:** 2-3 minutes
**Result:** Database ready, app can save data!
