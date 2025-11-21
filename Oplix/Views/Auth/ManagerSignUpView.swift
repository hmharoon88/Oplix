//
//  ManagerSignUpView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerSignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var showingError = false
    @State private var showingSuccess = false
    
    var body: some View {
        ZStack {
            Theme.primaryGradient
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
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Create Manager Account")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 20) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: {
                        Task { @MainActor in
                            guard !email.isEmpty, !password.isEmpty, !username.isEmpty else {
                                authViewModel.errorMessage = "Please fill in all fields"
                                showingError = true
                                return
                            }
                            
                            guard password == confirmPassword else {
                                authViewModel.errorMessage = "Passwords do not match"
                                showingError = true
                                return
                            }
                            
                            guard password.count >= 6 else {
                                authViewModel.errorMessage = "Password must be at least 6 characters"
                                showingError = true
                                return
                            }
                            
                            await authViewModel.signUp(email: email, password: password, username: username)
                            if let error = authViewModel.errorMessage {
                                showingError = true
                            } else {
                                showingSuccess = true
                            }
                        }
                    }) {
                        Text("Sign Up")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Theme.cloudBlue)
                            .cornerRadius(12)
                            .shadow(color: Theme.cloudBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(authViewModel.isLoading)
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
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Account created successfully! You can now sign in.")
        }
    }
}

#Preview {
    ManagerSignUpView()
        .environmentObject(AuthViewModel())
}

