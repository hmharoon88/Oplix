#!/usr/bin/env ruby
# Script to completely remove and re-add Firebase packages cleanly

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'

begin
  project = Xcodeproj::Project.open(project_path)
  
  puts "🔍 Finding Firebase package references..."
  
  # Find and remove Firebase package reference
  firebase_package = project.root_object.package_references.find { |ref| 
    ref.repositoryURL&.include?('firebase-ios-sdk') 
  }
  
  if firebase_package
    puts "  ✅ Found Firebase package, removing..."
    project.root_object.package_references.delete(firebase_package)
  end
  
  # Get the main target
  target = project.targets.find { |t| t.name == 'Oplix' }
  
  if target
    puts "  ✅ Found Oplix target, clearing package dependencies..."
    target.package_product_dependencies.clear
  end
  
  project.save
  puts ""
  puts "✅ Firebase packages removed from project"
  puts ""
  puts "📦 Next steps:"
  puts "   1. Open Xcode: open Oplix.xcodeproj"
  puts "   2. File → Add Package Dependencies..."
  puts "   3. Enter: https://github.com/firebase/firebase-ios-sdk"
  puts "   4. Select: FirebaseCore, FirebaseAuth, FirebaseFirestore"
  puts "   5. Click Add Package"
  puts ""
  puts "This will ensure a clean reinstall."
  
rescue LoadError
  puts "❌ Error: xcodeproj gem not installed"
  exit 1
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

