//
//  SupervisorLoginView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct SupervisorLoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var showingError = false
    
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
            
            VStack(spacing: 30) {
                // Back button
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Supervisor Login")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 20) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Login as: \(username.isEmpty ? "username" : username)@oplix.app")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Button(action: {
                        Task { @MainActor in
                            let email = "\(username)@oplix.app"
                            await authViewModel.signIn(email: email, password: password)
                            if authViewModel.errorMessage != nil {
                                showingError = true
                            } else {
                                dismiss()
                            }
                        }
                    }) {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .cornerRadius(12)
                            .shadow(color: Color.purple.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(authViewModel.isLoading || username.isEmpty)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.errorMessage ?? "Unknown error")
        }
    }
}

#Preview {
    SupervisorLoginView()
        .environmentObject(AuthViewModel())
}

