# Clean Reinstall of Firebase Packages

## The Problem

Xcode is having trouble resolving Firebase packages, showing errors like:
- "Missing package product 'FirebaseFirestore'"
- "Failed to fetch GTM Session Fetcher"

This usually happens when package resolution gets corrupted or stuck.

## Solution: Clean Reinstall

### Step 1: Remove Existing Packages

I've created a script to cleanly remove Firebase packages. Run:

```bash
cd /Users/haroon/Desktop/Oplix
ruby -I ~/.gem/ruby/2.6.0/gems remove_and_readd_firebase.rb
```

Or manually in Xcode:
1. Select project → Package Dependencies tab
2. Find `firebase-ios-sdk`
3. Click the "-" button to remove it

### Step 2: Clean All Caches

```bash
# Clean SwiftPM caches
rm -rf ~/Library/Developer/Xcode/SourcePackages
rm -rf ~/Library/Caches/org.swift.swiftpm

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/Oplix-*

# Clean project build
cd /Users/haroon/Desktop/Oplix
rm -rf build
```

### Step 3: Close Xcode

```bash
killall Xcode
```

### Step 4: Re-add Firebase in Xcode

1. **Open project:**
   ```bash
   open Oplix.xcodeproj
   ```

2. **Add Package:**
   - File → Add Package Dependencies...
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Click "Add Package"

3. **Select Products:**
   - ✅ FirebaseCore
   - ✅ FirebaseAuth  
   - ✅ FirebaseFirestore
   - Target: **Oplix** (not test targets)
   - Click "Add Package"

4. **Wait for Resolution:**
   - Watch the progress bar
   - Should complete in 1-2 minutes
   - If it takes longer than 3 minutes, see troubleshooting below

## Alternative: Use Specific Version

If network issues persist, try adding a specific version:

1. When adding package, click "Add to Project"
2. Change version rule to "Up to Next Major Version"
3. Set minimum version to `10.0.0`

## Troubleshooting Network Issues

If GTM Session Fetcher or other dependencies fail to fetch:

### Check Network
```bash
# Test GitHub connectivity
curl -I https://github.com/firebase/firebase-ios-sdk
curl -I https://github.com/google/gtm-session-fetcher
```

### Use Different Network
- Try a different Wi-Fi network
- Disable VPN if active
- Check firewall settings

### Manual Package Resolution
In Xcode:
1. File → Packages → Reset Package Caches
2. File → Packages → Resolve Package Versions
3. Wait for completion

## Verification

After re-adding, verify:
1. Open `FirebaseService.swift` - no red errors
2. Build project (⌘B) - should compile
3. Check Package Dependencies tab - all 3 products listed

## If Still Failing

If packages still won't resolve after clean reinstall:

1. **Check Xcode Version:**
   - Need Xcode 14.0+ for proper SPM support
   - Update if needed

2. **Try Binary Distribution:**
   - Some Firebase products have binary distributions
   - Check Firebase documentation for alternatives

3. **Use CocoaPods Instead:**
   - As a last resort, you could switch to CocoaPods
   - But SPM should work fine

