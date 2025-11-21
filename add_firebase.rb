#!/usr/bin/env ruby
# Script to add Firebase dependencies using the xcodeproj gem
# Install: gem install xcodeproj

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'

begin
  project = Xcodeproj::Project.open(project_path)
  
  # Check if Firebase is already added
  if project.root_object.package_references.any? { |ref| ref.repositoryURL&.include?('firebase-ios-sdk') }
    puts "✅ Firebase dependencies already added!"
    exit 0
  end
  
  # Create package reference
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = 'https://github.com/firebase/firebase-ios-sdk'
  package_ref.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => '10.0.0'
  }
  
  project.root_object.package_references << package_ref
  
  # Get the main target
  target = project.targets.find { |t| t.name == 'Oplix' }
  
  unless target
    puts "❌ Error: Could not find 'Oplix' target"
    exit 1
  end
  
  # Create package product dependencies
  products = ['FirebaseCore', 'FirebaseAuth', 'FirebaseFirestore']
  
  products.each do |product_name|
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = product_name
    dep.package = package_ref
    
    target.package_product_dependencies << dep
  end
  
  # Also add to frameworks build phase (sometimes needed)
  frameworks_build_phase = target.frameworks_build_phase
  if frameworks_build_phase
    products.each do |product_name|
      # Check if already added
      existing = frameworks_build_phase.files.find do |file|
        file.file_ref && file.file_ref.respond_to?(:name) && file.file_ref.name == product_name
      end
      
      unless existing
        # Create a file reference for the framework (SPM handles this automatically, but we ensure it's there)
        file_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
        file_ref.name = product_name
        file_ref.path = product_name
        file_ref.source_tree = 'BUILT_PRODUCTS_DIR'
        
        build_file = frameworks_build_phase.add_file_reference(file_ref)
        build_file.settings = { 'ATTRIBUTES' => ['Weak'] } if build_file.respond_to?(:settings=)
      end
    end
  end
  
  project.save
  
  puts "✅ Firebase dependencies added successfully!"
  puts "📦 Products added: #{products.join(', ')}"
  puts ""
  puts "Next steps:"
  puts "  1. Open the project in Xcode"
  puts "  2. Xcode will automatically resolve packages"
  puts "  3. Or run: xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj"
  
rescue LoadError
  puts "❌ Error: xcodeproj gem not installed"
  puts ""
  puts "Install it with:"
  puts "  gem install xcodeproj"
  puts ""
  puts "Or use the Xcode UI method (File → Add Package Dependencies...)"
  exit 1
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

