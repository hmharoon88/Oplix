#!/usr/bin/env ruby
# Script to fix Firebase package linking issues

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'

begin
  project = Xcodeproj::Project.open(project_path)
  
  # Find Firebase package reference
  firebase_package = project.root_object.package_references.find { |ref| 
    ref.repositoryURL&.include?('firebase-ios-sdk') 
  }
  
  unless firebase_package
    puts "❌ Firebase package not found!"
    exit 1
  end
  
  puts "✅ Found Firebase package reference"
  
  # Get the main target
  target = project.targets.find { |t| t.name == 'Oplix' }
  
  unless target
    puts "❌ Error: Could not find 'Oplix' target"
    exit 1
  end
  
  # Remove existing package product dependencies
  target.package_product_dependencies.clear
  
  # Re-add package product dependencies properly
  products = ['FirebaseCore', 'FirebaseAuth', 'FirebaseFirestore']
  
  products.each do |product_name|
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = product_name
    dep.package = firebase_package
    
    target.package_product_dependencies << dep
    puts "  ✅ Added #{product_name}"
  end
  
  project.save
  
  puts ""
  puts "✅ Firebase dependencies re-linked successfully!"
  puts "📦 Next: Close and reopen Xcode, or run:"
  puts "   xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj"
  
rescue LoadError
  puts "❌ Error: xcodeproj gem not installed"
  exit 1
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

