#!/usr/bin/env python3
"""
Safer script to add Firebase dependencies by creating a proper Xcode project modification.
This script carefully inserts the required sections without breaking the project structure.
"""

import re
import sys
import uuid

PROJECT_FILE = "Oplix.xcodeproj/project.pbxproj"

def generate_uuid():
    """Generate a 24-character hex UUID for Xcode project"""
    return ''.join([format(int(x, 16), 'X') for x in str(uuid.uuid4()).replace('-', '')[:24]]).upper()[:24]

def add_firebase_dependencies():
    """Add Firebase package dependencies to project.pbxproj safely"""
    
    try:
        with open(PROJECT_FILE, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: {PROJECT_FILE} not found!")
        sys.exit(1)
    
    # Check if already added
    content = ''.join(lines)
    if 'firebase-ios-sdk' in content:
        print("✅ Firebase dependencies already added!")
        return
    
    # Generate UUIDs
    package_ref_uuid = generate_uuid()
    firebase_core_uuid = generate_uuid()
    firebase_auth_uuid = generate_uuid()
    firebase_firestore_uuid = generate_uuid()
    
    new_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        new_lines.append(line)
        
        # 1. Add package reference after PBXFileReference section
        if '/* End PBXFileReference section */' in line:
            new_lines.append(f'\t\t{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{isa = PBXFileReference; }};\n')
        
        # 2. Add packageReferences to project section
        elif 'projectRoot = "";' in line:
            new_lines.append(line)
            new_lines.append(f'\t\t\tpackageReferences = (\n')
            new_lines.append(f'\t\t\t\t{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,\n')
            new_lines.append(f'\t\t\t);\n')
            i += 1
            continue
        
        # 3. Add packageProductDependencies to Oplix target
        elif 'BED8D3FD2ECB9D5D00863EFC /* Oplix */' in line and i + 5 < len(lines):
            # Look ahead to find packageProductDependencies
            j = i
            found_target = False
            while j < min(i + 20, len(lines)):
                if 'packageProductDependencies = (' in lines[j]:
                    found_target = True
                    # Find the closing parenthesis
                    k = j
                    while k < min(j + 5, len(lines)):
                        if ');' in lines[k] and lines[k].strip() == ');':
                            # Insert dependencies
                            new_lines.append(lines[j])  # packageProductDependencies = (
                            new_lines.append(f'\t\t\t\t{firebase_core_uuid} /* FirebaseCore */,\n')
                            new_lines.append(f'\t\t\t\t{firebase_auth_uuid} /* FirebaseAuth */,\n')
                            new_lines.append(f'\t\t\t\t{firebase_firestore_uuid} /* FirebaseFirestore */,\n')
                            new_lines.append(lines[k])  # );
                            i = k
                            break
                        k += 1
                    break
                j += 1
            if found_target:
                i += 1
                continue
        
        # 4. Add XCRemoteSwiftPackageReference section before XCConfigurationList
        elif '/* Begin XCConfigurationList section */' in line:
            ref_section = f'''/* Begin XCRemoteSwiftPackageReference section */
		{package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/firebase/firebase-ios-sdk";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 10.0.0;
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

'''
            new_lines.insert(-1, ref_section)
        
        # 5. Add XCSwiftPackageProductDependency section
        elif '/* End XCRemoteSwiftPackageReference section */' in line:
            new_lines.append(line)
            dep_section = f'''/* Begin XCSwiftPackageProductDependency section */
		{firebase_core_uuid} /* FirebaseCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseCore;
		}};
		{firebase_auth_uuid} /* FirebaseAuth */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseAuth;
		}};
		{firebase_firestore_uuid} /* FirebaseFirestore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {package_ref_uuid} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseFirestore;
		}};
/* End XCSwiftPackageProductDependency section */
'''
            new_lines.append(dep_section)
        
        i += 1
    
    # Write back
    with open(PROJECT_FILE, 'w') as f:
        f.writelines(new_lines)
    
    print("✅ Firebase dependencies added to project.pbxproj")
    print("📦 Next: Open in Xcode to resolve packages, or run:")
    print("   xcodebuild -resolvePackageDependencies -project Oplix.xcodeproj")

if __name__ == "__main__":
    add_firebase_dependencies()

