# Adding Firebase iOS SDK via Xcode

## Step-by-Step Instructions

### Method 1: Add Package Dependencies (Recommended)

1. **Open your project in Xcode**
   ```bash
   open Oplix.xcodeproj
   ```

2. **Add the Package**
   - In Xcode, go to **File** → **Add Package Dependencies...**
   - Or right-click on the project in the navigator → **Add Package Dependencies...**

3. **Enter the Package URL**
   - In the search bar, paste: `https://github.com/firebase/firebase-ios-sdk`
   - Click **Add Package**

4. **Select Products**
   - When prompted, select these products:
     - ✅ **FirebaseCore** (required)
     - ✅ **FirebaseAuth** (for authentication)
     - ✅ **FirebaseFirestore** (for database)
   - Make sure the target is set to **Oplix** (not the test targets)
   - Click **Add Package**

5. **Wait for Resolution**
   - Xcode will download and resolve the packages
   - Watch the progress bar at the top
   - This may take 1-2 minutes

### Method 2: Verify Current Setup

If you already added it via CLI, verify it's working:

1. **Check Package Dependencies**
   - In Xcode, select your project in the navigator
   - Select the **Oplix** target
   - Go to **Package Dependencies** tab
   - You should see `firebase-ios-sdk` listed

2. **Resolve Packages**
   - Go to **File** → **Packages** → **Resolve Package Versions**
   - Wait for it to complete

3. **Check Frameworks**
   - Go to **General** tab → **Frameworks, Libraries, and Embedded Content**
   - You should see FirebaseCore, FirebaseAuth, FirebaseFirestore listed

## Troubleshooting

### If packages don't appear:
1. Close Xcode completely
2. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/Oplix-*`
3. Reopen the project
4. Try adding the package again

### If you see "Missing package product" errors:
1. Go to **File** → **Packages** → **Reset Package Caches**
2. Then **File** → **Packages** → **Resolve Package Versions**
3. Wait for Xcode to finish processing

## Verification

After adding, verify in your code:
- Open `FirebaseService.swift`
- The imports should work without errors:
  ```swift
  import FirebaseAuth
  import FirebaseFirestore
  ```

## Next Steps

After adding Firebase:
1. Add `GoogleService-Info.plist` from Firebase Console
2. Enable Authentication in Firebase Console
3. Set up Firestore Database

