# Firebase Setup Instructions

## Quick Fix: Add Firebase SDK to Xcode Project

The error "No such module 'FirebaseAuth'" occurs because Firebase hasn't been added to the project yet. Follow these steps:

### Step 1: Add Firebase Package Dependency

1. **Open your project in Xcode**
   - Open `Oplix.xcodeproj` in Xcode

2. **Add Package Dependency**
   - In Xcode, go to **File** → **Add Package Dependencies...**
   - In the search bar, paste: `https://github.com/firebase/firebase-ios-sdk`
   - Click **Add Package**
   - Wait for Xcode to resolve the package

3. **Select Required Products**
   - When prompted, select these products:
     - ✅ **FirebaseAuth**
     - ✅ **FirebaseFirestore**
     - ✅ **FirebaseCore**
   - Make sure the target is set to **Oplix** (not OplixTests or OplixUITests)
   - Click **Add Package**

4. **Wait for Download**
   - Xcode will download and integrate the Firebase SDK
   - This may take a minute or two

### Step 2: Verify Installation

After adding the package, the error should disappear. You can verify by:
- Building the project (⌘B)
- The "No such module 'FirebaseAuth'" error should be gone

### Step 3: Add GoogleService-Info.plist (Required for Runtime)

1. **Create Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Create a new project or select existing one

2. **Add iOS App**
   - Click "Add app" → Select iOS
   - Enter your bundle identifier: `tech.Oplix` (or check your project settings)
   - Register the app

3. **Download GoogleService-Info.plist**
   - Download the `GoogleService-Info.plist` file
   - Drag and drop it into your Xcode project (into the `Oplix` folder)
   - Make sure "Copy items if needed" is checked
   - Make sure it's added to the Oplix target

### Step 4: Enable Firebase Services

1. **Enable Authentication**
   - In Firebase Console → Authentication → Sign-in method
   - Enable "Email/Password"

2. **Create Firestore Database**
   - In Firebase Console → Firestore Database
   - Click "Create database"
   - Start in production mode
   - Choose a location
   - Copy the rules from `firestore.rules` to your Firestore Rules

### Troubleshooting

If you still see errors after adding the package:

1. **Clean Build Folder**
   - Product → Clean Build Folder (⇧⌘K)
   - Then build again (⌘B)

2. **Check Package Resolution**
   - File → Packages → Reset Package Caches
   - File → Packages → Resolve Package Versions

3. **Verify Target Membership**
   - Select `GoogleService-Info.plist` in Xcode
   - In File Inspector, ensure "Oplix" target is checked

## Alternative: Manual Package.swift (Advanced)

If you prefer to use a Package.swift file, you can create one, but for iOS apps, using Xcode's built-in SPM is recommended.

