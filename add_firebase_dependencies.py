#!/usr/bin/env python3
"""
Script to add Firebase Swift Package Manager dependencies to Xcode project
"""

import re
import sys
import uuid

PROJECT_FILE = "Oplix.xcodeproj/project.pbxproj"

def generate_uuid():
    """Generate a 24-character hex UUID for Xcode project"""
    return ''.join([format(int(x, 16), 'X') for x in str(uuid.uuid4()).replace('-', '')[:24]])

def add_firebase_dependencies():
    """Add Firebase package dependencies to project.pbxproj"""
    
    try:
        with open(PROJECT_FILE, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {PROJECT_FILE} not found!")
        sys.exit(1)
    
    # Generate UUIDs for package references
    package_ref_uuid = generate_uuid()
    firebase_auth_uuid = generate_uuid()
    firebase_firestore_uuid = generate_uuid()
    firebase_core_uuid = generate_uuid()
    
    # Check if Firebase is already added
    if 'firebase-ios-sdk' in content:
        print("Firebase dependencies already added!")
        return
    
    # 1. Add package reference to PBXFileReference section
    file_ref_section = r'(/\* End PBXFileReference section \*\/)'
    package_ref_entry = f'\t\t{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https://github.com/firebase/firebase-ios-sdk";\n\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 10.0.0;\n\t\t\t}};\n\t\t}};\n'
    content = re.sub(file_ref_section, package_ref_entry + r'\1', content)
    
    # 2. Add package reference to project's packageReferences
    project_section = r'(BED8D3F62ECB9D5D00863EFC /\* Project object \*\/ = \{[\s\S]*?projectRoot = "";)'
    package_refs = f'\n\t\t\tpackageReferences = (\n\t\t\t\t{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,\n\t\t\t);'
    content = re.sub(
        r'(projectRoot = "";)',
        r'\1' + package_refs,
        content
    )
    
    # 3. Add package product dependencies to Oplix target
    target_section = r'(BED8D3FD2ECB9D5D00863EFC /\* Oplix \*\/ = \{[\s\S]*?packageProductDependencies = \([\s\S]*?\);)'
    package_deps = f'\n\t\t\t\t{firebase_core_uuid} /* FirebaseCore */,\n\t\t\t\t{firebase_auth_uuid} /* FirebaseAuth */,\n\t\t\t\t{firebase_firestore_uuid} /* FirebaseFirestore */,'
    content = re.sub(
        r'(packageProductDependencies = \(\s*\);)',
        lambda m: m.group(1).replace(')', package_deps + '\n\t\t\t);'),
        content,
        count=1  # Only replace the first occurrence (Oplix target)
    )
    
    # 4. Add XCRemoteSwiftPackageReference section
    remote_package_section = r'(/\* End XCConfigurationList section \*\/)'
    remote_package_entry = f'\n\t/* Begin XCRemoteSwiftPackageReference section */\n\t\t{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https://github.com/firebase/firebase-ios-sdk";\n\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 10.0.0;\n\t\t\t}};\n\t\t}};\n\t/* End XCRemoteSwiftPackageReference section */\n'
    content = re.sub(remote_package_section, remote_package_entry + r'\1', content)
    
    # 5. Add XCSwiftPackageProductDependency section
    swift_package_section = r'(/\* End XCRemoteSwiftPackageReference section \*\/)'
    swift_package_entry = f'\n\t/* Begin XCSwiftPackageProductDependency section */\n\t\t{firebase_core_uuid} /* FirebaseCore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;\n\t\t\tproductName = FirebaseCore;\n\t\t}};\n\t\t{firebase_auth_uuid} /* FirebaseAuth */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;\n\t\t\tproductName = FirebaseAuth;\n\t\t}};\n\t\t{firebase_firestore_uuid} /* FirebaseFirestore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;\n\t\t\tproductName = FirebaseFirestore;\n\t\t}};\n\t/* End XCSwiftPackageProductDependency section */\n'
    content = re.sub(swift_package_section, swift_package_entry + r'\1', content)
    
    # Write back to file
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)
    
    print("✅ Firebase dependencies added to project.pbxproj")
    print("📦 Next steps:")
    print("   1. Open the project in Xcode")
    print("   2. Xcode will automatically resolve the packages")
    print("   3. Or run: xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj")

if __name__ == "__main__":
    add_firebase_dependencies()

