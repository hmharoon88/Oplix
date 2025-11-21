#!/bin/bash
# Script to verify Firebase dependencies are properly set up

echo "🔍 Verifying Firebase setup..."

# Check if packages are resolved
echo ""
echo "📦 Checking package resolution..."
xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj -scheme Oplix 2>&1 | grep -E "(Resolved|Firebase)" | head -3

# Check project file
echo ""
echo "📄 Checking project file..."
if grep -q "FirebaseFirestore" Oplix.xcodeproj/project.pbxproj; then
    echo "✅ FirebaseFirestore found in project"
else
    echo "❌ FirebaseFirestore NOT found in project"
fi

if grep -q "FirebaseAuth" Oplix.xcodeproj/project.pbxproj; then
    echo "✅ FirebaseAuth found in project"
else
    echo "❌ FirebaseAuth NOT found in project"
fi

if grep -q "FirebaseCore" Oplix.xcodeproj/project.pbxproj; then
    echo "✅ FirebaseCore found in project"
else
    echo "❌ FirebaseCore NOT found in project"
fi

echo ""
echo "💡 If you still see 'Missing package product' errors:"
echo "   1. Close Xcode completely"
echo "   2. Run: rm -rf ~/Library/Developer/Xcode/DerivedData/Oplix-*"
echo "   3. Reopen the project in Xcode"
echo "   4. Wait for Xcode to finish processing packages (watch the progress bar)"
echo "   5. Try building again"

