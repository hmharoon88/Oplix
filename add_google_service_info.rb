#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'Oplix.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'Oplix' }
unless target
  puts "❌ Error: Could not find target 'Oplix'"
  exit 1
end

# Find the Oplix group
main_group = project.main_group['Oplix']
unless main_group
  puts "❌ Error: Could not find 'Oplix' group"
  exit 1
end

# Check if GoogleService-Info.plist already exists in the project
plist_path = 'Oplix/GoogleService-Info.plist'
existing_file = main_group.files.find { |f| f.path == 'GoogleService-Info.plist' }

if existing_file
  puts "✅ GoogleService-Info.plist already exists in project"
else
  # Add the file reference
  file_ref = main_group.new_file(plist_path)
  puts "✅ Added GoogleService-Info.plist to project"
end

# Ensure it's added to the resources build phase
resources_phase = target.resources_build_phase
file_ref ||= main_group.files.find { |f| f.path == 'GoogleService-Info.plist' }

if file_ref
  # Check if already in resources phase
  unless resources_phase.files.any? { |f| f.file_ref == file_ref }
    resources_phase.add_file_reference(file_ref)
    puts "✅ Added GoogleService-Info.plist to Copy Bundle Resources"
  else
    puts "✅ GoogleService-Info.plist already in Copy Bundle Resources"
  end
end

project.save
puts "✅ Project saved successfully!"

