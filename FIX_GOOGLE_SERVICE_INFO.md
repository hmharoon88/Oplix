# Fix: Firebase Core Error Domain

## Problem
You're seeing `[NSException raise:kFirebaseCoreErrorDomain` error. This means Firebase can't find `GoogleService-Info.plist` in the app bundle.

## Solution

The `GoogleService-Info.plist` file has been copied to `Oplix/GoogleService-Info.plist`. However, with Xcode's new file system synchronization, you may need to manually ensure it's included in the build.

### Option 1: Add via Xcode (Recommended)

1. **Open the project in Xcode**
   ```bash
   open Oplix.xcodeproj
   ```

2. **Verify the file exists**
   - In Xcode's Project Navigator, check if `GoogleService-Info.plist` appears under the `Oplix` folder
   - If it doesn't appear, right-click the `Oplix` folder → **Add Files to "Oplix"...**
   - Select `Oplix/GoogleService-Info.plist`
   - Make sure "Copy items if needed" is **unchecked** (file is already in the right place)
   - Make sure "Add to targets: Oplix" is **checked**
   - Click **Add**

3. **Verify it's in Copy Bundle Resources**
   - Select the **Oplix** target in the project navigator
   - Go to **Build Phases** tab
   - Expand **Copy Bundle Resources**
   - Verify `GoogleService-Info.plist` is listed
   - If not, click the **+** button and add it

4. **Clean and rebuild**
   - Product → Clean Build Folder (⇧⌘K)
   - Product → Build (⌘B)

### Option 2: Verify Bundle ID Matches

Make sure the bundle ID in `GoogleService-Info.plist` matches your app's bundle ID:

1. Check your app's bundle ID:
   - Select the **Oplix** target
   - Go to **General** tab
   - Check **Bundle Identifier** (should be `tech.Oplix`)

2. Verify `GoogleService-Info.plist` has the same bundle ID:
   - Open `Oplix/GoogleService-Info.plist`
   - Check the `BUNDLE_ID` key matches `tech.Oplix`

### Option 3: Manual Verification

After adding the file, verify it's in the app bundle:

1. Build the app
2. Check the build output:
   ```bash
   xcodebuild -project Oplix.xcodeproj -scheme Oplix -sdk iphonesimulator build
   ```
3. Verify the file is copied:
   ```bash
   find ~/Library/Developer/Xcode/DerivedData -name "Oplix.app" -type d | head -1 | xargs -I {} find {} -name "GoogleService-Info.plist"
   ```

## Current Status

✅ `GoogleService-Info.plist` exists at `Oplix/GoogleService-Info.plist`
✅ Bundle ID in plist: `tech.Oplix`
⏳ File needs to be explicitly added to Xcode project (if not auto-detected)

## Next Steps

1. Open the project in Xcode
2. Verify `GoogleService-Info.plist` is visible in Project Navigator
3. Ensure it's added to the **Oplix** target
4. Clean and rebuild

The file should now be included in the app bundle and Firebase should initialize correctly.

