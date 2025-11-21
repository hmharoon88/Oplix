#!/bin/bash
# Script to add Firebase dependencies using Xcode command line tools

set -e

PROJECT_FILE="Oplix.xcodeproj/project.pbxproj"
PACKAGE_URL="https://github.com/firebase/firebase-ios-sdk"

echo "🔧 Adding Firebase dependencies to Xcode project..."

# Check if xcodebuild is available
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ xcodebuild not found. Please install Xcode Command Line Tools."
    exit 1
fi

# Method 1: Try using xcodebuild (requires Xcode 11+)
# Note: This method requires the project to be opened in Xcode first or using a different approach

# Method 2: Use a Ruby script with xcodeproj gem (if available)
if command -v ruby &> /dev/null && gem list xcodeproj -i &> /dev/null; then
    echo "📦 Using xcodeproj gem..."
    ruby << 'RUBY_SCRIPT'
require 'xcodeproj'

project_path = 'Oplix.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add Firebase package
firebase_package = project.new_file('https://github.com/firebase/firebase-ios-sdk')
project.root_object.package_references << firebase_package

# Get the main target
target = project.targets.find { |t| t.name == 'Oplix' }

# Add package products
firebase_core = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
firebase_core.product_name = 'FirebaseCore'
firebase_core.package = firebase_package

firebase_auth = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
firebase_auth.product_name = 'FirebaseAuth'
firebase_auth.package = firebase_package

firebase_firestore = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
firebase_firestore.product_name = 'FirebaseFirestore'
firebase_firestore.package = firebase_package

target.package_product_dependencies << firebase_core
target.package_product_dependencies << firebase_auth
target.package_product_dependencies << firebase_firestore

project.save
puts "✅ Firebase dependencies added successfully!"
RUBY_SCRIPT
    exit 0
fi

# Method 3: Manual instructions
echo ""
echo "⚠️  Automated CLI method not available."
echo "📝 Please use one of these methods:"
echo ""
echo "Method A - Xcode UI (Recommended):"
echo "  1. Open Oplix.xcodeproj in Xcode"
echo "  2. File → Add Package Dependencies..."
echo "  3. Enter: $PACKAGE_URL"
echo "  4. Select: FirebaseCore, FirebaseAuth, FirebaseFirestore"
echo ""
echo "Method B - Install xcodeproj gem:"
echo "  gem install xcodeproj"
echo "  Then run this script again"
echo ""

exit 1

