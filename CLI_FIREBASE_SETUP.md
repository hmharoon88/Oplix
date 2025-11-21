# Adding Firebase Dependencies via CLI

## Summary

Unfortunately, Xcode doesn't provide a pure CLI command to add Swift Package Manager dependencies. However, here are your **CLI-compatible options**:

## ✅ Option 1: Ruby xcodeproj Gem (Best CLI Solution)

This is the standard tool for programmatically modifying Xcode projects.

### Install the gem:
```bash
gem install xcodeproj
```

### Run the script:
```bash
cd /Users/haroon/Desktop/Oplix
ruby add_firebase.rb
```

The script (`add_firebase.rb`) will:
- Add Firebase package reference
- Add FirebaseCore, FirebaseAuth, and FirebaseFirestore products
- Link them to the Oplix target

### Then resolve packages:
```bash
xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj -scheme Oplix
```

## ✅ Option 2: One-Time Xcode UI + CLI After

**Fastest method (30 seconds):**

1. Open `Oplix.xcodeproj` in Xcode
2. **File** → **Add Package Dependencies...**
3. Enter: `https://github.com/firebase/firebase-ios-sdk`
4. Select: **FirebaseCore**, **FirebaseAuth**, **FirebaseFirestore**
5. Click **Add Package**

After this one-time setup, you can use CLI commands:
```bash
# Build
xcodebuild -project Oplix.xcodeproj -scheme Oplix

# Resolve packages
xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj
```

## ✅ Option 3: XcodeGen (For CI/CD)

If you're setting up CI/CD, consider using XcodeGen to define your project in YAML:

```bash
brew install xcodegen
```

Then define dependencies in `project.yml` and generate the project.

## Current Status

Your project is ready - you just need to add the Firebase SDK dependency. The code is complete and will compile once Firebase is added.

## Quick Test

After adding Firebase (via any method above), verify it works:

```bash
# Check if project is valid
xcodebuild -list -project Oplix.xcodeproj

# Try building (will fail without GoogleService-Info.plist, but should compile)
xcodebuild -project Oplix.xcodeproj -scheme Oplix -sdk iphonesimulator
```

## Recommendation

**For immediate use:** Use Option 2 (Xcode UI) - it's the fastest and most reliable.

**For automation/CI:** Use Option 1 (Ruby gem) or Option 3 (XcodeGen).

