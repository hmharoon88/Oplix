#!/bin/bash
# Script to fix stuck Xcode package resolution

echo "🔧 Fixing stuck Xcode package resolution..."

# 1. Kill Xcode if it's stuck
echo "1. Stopping Xcode..."
killall Xcode 2>/dev/null
sleep 2

# 2. Clean derived data
echo "2. Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Oplix-* 2>/dev/null
echo "   ✅ Derived data cleaned"

# 3. Clean package caches
echo "3. Cleaning package caches..."
rm -rf ~/Library/Developer/Xcode/SourcePackages 2>/dev/null
rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null
echo "   ✅ Package caches cleaned"

# 4. Clean project build folder
echo "4. Cleaning project build folder..."
cd /Users/haroon/Desktop/Oplix
rm -rf build 2>/dev/null
echo "   ✅ Build folder cleaned"

# 5. Try resolving via command line
echo "5. Resolving packages via command line..."
xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj -scheme Oplix 2>&1 | tail -5

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Next steps:"
echo "  1. Reopen Xcode: open Oplix.xcodeproj"
echo "  2. Wait 30-60 seconds for packages to resolve"
echo "  3. If still stuck, try: File → Packages → Reset Package Caches"

