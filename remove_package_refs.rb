#!/usr/bin/env ruby
# Remove package product dependencies so Xcode can add them fresh

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'

begin
  project = Xcodeproj::Project.open(project_path)
  
  # Get the main target
  target = project.targets.find { |t| t.name == 'Oplix' }
  
  if target
    puts "✅ Found Oplix target"
    puts "  Removing package product dependencies..."
    target.package_product_dependencies.clear
    project.save
    puts "✅ Removed package dependencies from target"
    puts ""
    puts "Now in Xcode:"
    puts "  1. File → Add Package Dependencies..."
    puts "  2. Enter: https://github.com/firebase/firebase-ios-sdk"
    puts "  3. Select products and Oplix target (should not be greyed out now)"
  else
    puts "❌ Could not find Oplix target"
  end
  
rescue LoadError
  puts "❌ Error: xcodeproj gem not installed"
  exit 1
rescue => e
  puts "❌ Error: #{e.message}"
  exit 1
end

