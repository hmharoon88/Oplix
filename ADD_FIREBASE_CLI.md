# Adding Firebase via CLI

Unfortunately, directly modifying Xcode project files (`.pbxproj`) programmatically is error-prone and can corrupt the project. Here are the **recommended CLI-compatible methods**:

## Method 1: Using Xcode Command Line (Recommended)

The most reliable way is to use Xcode's built-in package resolution after manually adding the package reference. However, Xcode doesn't provide a pure CLI command to add SPM packages.

## Method 2: Use XcodeGen (Best for CI/CD)

If you want a truly CLI-based workflow, consider using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
# Install XcodeGen
brew install xcodegen

# Create project.yml with Firebase dependencies
# Then generate the project
xcodegen generate
```

## Method 3: Manual Addition + CLI Resolution

1. **Add package reference manually once** (or use the script below as a starting point)
2. **Resolve packages via CLI:**

```bash
# After adding the package reference, resolve dependencies
xcodebuild -resolvePackageDependencies \
  -project Oplix.xcodeproj \
  -scheme Oplix
```

## Method 4: Use Ruby xcodeproj Gem

```bash
# Install the gem
gem install xcodeproj

# Run Ruby script to add dependencies
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Oplix.xcodeproj')
# Add package reference and products
project.save
"
```

## Current Recommendation

**For now, the safest approach is:**

1. Open the project in Xcode once
2. Add Firebase via File → Add Package Dependencies
3. After that, you can use CLI commands like `xcodebuild` for building/resolving

The project file will then be properly formatted and you can commit it to version control.

## Quick Xcode UI Method (30 seconds)

1. Open `Oplix.xcodeproj` in Xcode
2. **File** → **Add Package Dependencies...**
3. Paste: `https://github.com/firebase/firebase-ios-sdk`
4. Select: **FirebaseCore**, **FirebaseAuth**, **FirebaseFirestore**
5. Click **Add Package**

This is the most reliable method and takes less than a minute.

