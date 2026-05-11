//
//  ManagerLoginView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ManagerLoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var showingError = false
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @State private var showingResendVerification = false
    @State private var needsVerification = false
    
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
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Oplix Owner")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 20) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: {
                        Task { @MainActor in
                            await authViewModel.signIn(email: email, password: password)
                            if authViewModel.errorMessage != nil {
                                // Check if error is about email verification
                                if authViewModel.errorMessage?.contains("verify your email") == true {
                                    needsVerification = true
                                    showingResendVerification = true
                                } else {
                                    showingError = true
                                }
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
                            .background(Theme.cloudBlue)
                            .cornerRadius(12)
                            .shadow(color: Theme.cloudBlue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(authViewModel.isLoading)
                    
                    // Forgot Password button
                    Button(action: {
                        showingForgotPassword = true
                    }) {
                        Text("Forgot Password?")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // Sign Up button
                    Button(action: {
                        showingSignUp = true
                    }) {
                        Text("Don't have an account? Sign Up")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
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
        .alert("Email Verification Required", isPresented: $showingResendVerification) {
            Button("Resend Verification Email") {
                Task { @MainActor in
                    let success = await authViewModel.resendVerificationEmail(email: email, password: password)
                    if success {
                        showingResendVerification = false
                        showingError = true
                        authViewModel.errorMessage = "Verification email resent! Please check your inbox (and spam folder) and click the verification link."
                    } else {
                        showingError = true
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please verify your email before signing in. Check your inbox (and spam folder) for the verification link. If you didn't receive it, tap 'Resend Verification Email'.")
        }
        .fullScreenCover(isPresented: $showingSignUp) {
            ManagerSignUpView()
                .environmentObject(authViewModel)
        }
        .fullScreenCover(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
                .environmentObject(authViewModel)
        }
    }
    
}

#Preview {
    ManagerLoginView()
        .environmentObject(AuthViewModel())
}
