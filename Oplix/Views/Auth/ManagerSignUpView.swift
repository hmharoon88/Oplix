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
    @State private var showingError = false
    @State private var showingSuccess = false
    @State private var verificationEmailSent = false
    @State private var showingResendOption = false
    
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
                
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.white)
                    
                    Text("Create Manager Account")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .oplixCompactFormField()
                    
                    SecureField("Password", text: $password)
                        .oplixCompactFormField()
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .oplixCompactFormField()
                    
                    Button(action: {
                        Task { @MainActor in
                            guard !email.isEmpty, !password.isEmpty else {
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
                            
                            // Generate username from email (use part before @)
                            let username = email.components(separatedBy: "@").first ?? email
                            let success = await authViewModel.signUp(email: email, password: password, username: username)
                            if success {
                                verificationEmailSent = true
                                showingSuccess = true
                            } else {
                                showingError = true
                            }
                        }
                    }) {
                        Text("Sign Up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Theme.cloudBlue)
                            .cornerRadius(11)
                            .shadow(color: Theme.cloudBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(authViewModel.isLoading)
                }
                .oplixCompactGlassCard(maxWidth: 380)
                .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.errorMessage ?? "Unknown error")
        }
        .alert("Verification Email Sent", isPresented: $showingSuccess) {
            Button("Resend Email") {
                Task { @MainActor in
                    let success = await authViewModel.resendVerificationEmail(email: email, password: password)
                    if success {
                        showingSuccess = true
                    } else {
                        showingError = true
                    }
                }
            }
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("A verification email has been sent to \(email). Please check your inbox (and spam folder) and click the verification link before signing in. If you don't receive it, tap 'Resend Email'.")
        }
    }
}

#Preview {
    ManagerSignUpView()
        .environmentObject(AuthViewModel())
}

