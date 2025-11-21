//
//  RoleSelectionView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct RoleSelectionView: View {
    @State private var selectedRole: User.UserRole?
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                    Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.white)
                    
                    Text("Oplix")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Cloud-Based Management")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                VStack(spacing: 20) {
                    Button(action: {
                        selectedRole = .manager
                    }) {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.title2)
                            Text("Manager")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton(backgroundColor: Theme.cloudBlue)
                    }
                    
                    Button(action: {
                        selectedRole = .employee
                    }) {
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.title2)
                            Text("Employee")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton(backgroundColor: Theme.sunshineYellow)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .fullScreenCover(item: $selectedRole) { role in
            if role == .manager {
                ManagerLoginView()
                    .environmentObject(authViewModel)
            } else {
                EmployeeLoginView()
                    .environmentObject(authViewModel)
            }
        }
    }
}

extension User.UserRole: Identifiable {
    public var id: String { rawValue }
}

#Preview {
    RoleSelectionView()
        .environmentObject(AuthViewModel())
}
