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
            
            VStack(spacing: 20) {
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
                
                Image(systemName: "cloud.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .oplixCompactFormField()
                    
                    SecureField("Password", text: $password)
                        .oplixCompactFormField()
                    
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
                    
                    // Forgot Password button
                    Button(action: {
                        showingForgotPassword = true
                    }) {
                        Text("Forgot Password?")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(red: 0.12, green: 0.35, blue: 0.62))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    
                    // Sign Up button
                    Button(action: {
                        showingSignUp = true
                    }) {
                        Text("Don't have an account? Sign Up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.cloudBlue)
                            .cornerRadius(10)
                    }
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
