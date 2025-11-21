#!/usr/bin/env ruby
# Script to add Firebase products to the target

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'

begin
  project = Xcodeproj::Project.open(project_path)
  
  # Find Firebase package
  firebase_package = project.root_object.package_references.find { |ref| 
    ref.repositoryURL&.include?('firebase-ios-sdk') 
  }
  
  unless firebase_package
    puts "❌ Firebase package not found!"
    puts "Please add it via Xcode: File → Add Package Dependencies..."
    exit 1
  end
  
  puts "✅ Found Firebase package"
  
  # Get the main target
  target = project.targets.find { |t| t.name == 'Oplix' }
  
  unless target
    puts "❌ Error: Could not find 'Oplix' target"
    exit 1
  end
  
  puts "✅ Found Oplix target"
  
  # Clear existing Firebase dependencies
  target.package_product_dependencies.reject! { |dep| 
    ['FirebaseCore', 'FirebaseAuth', 'FirebaseFirestore'].include?(dep.product_name)
  }
  
  # Add package product dependencies
  products = ['FirebaseCore', 'FirebaseAuth', 'FirebaseFirestore']
  
  products.each do |product_name|
    # Check if already exists
    existing = target.package_product_dependencies.find { |dep| dep.product_name == product_name }
    
    unless existing
      dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
      dep.product_name = product_name
      dep.package = firebase_package
      
      target.package_product_dependencies << dep
      puts "  ✅ Added #{product_name}"
    else
      puts "  ℹ️  #{product_name} already exists"
    end
  end
  
  project.save
  
  puts ""
  puts "✅ Firebase products added to target!"
  puts ""
  puts "Next: In Xcode, go to File → Packages → Resolve Package Versions"
  puts "Or wait for Xcode to automatically resolve packages."
  
rescue LoadError
  puts "❌ Error: xcodeproj gem not installed"
  exit 1
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

