//
//  ForgotPasswordView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var showingError = false
    @State private var showingSuccess = false
    
    var body: some View {
        ZStack {
            Theme.primaryGradient
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
                
                VStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.white)
                    
                    Text("Reset Password")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 12) {
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    TextField("Email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .oplixCompactFormField()
                    
                    Button(action: {
                        Task { @MainActor in
                            guard !email.isEmpty else {
                                authViewModel.errorMessage = "Please enter your email address"
                                showingError = true
                                return
                            }
                            
                            await authViewModel.resetPassword(email: email)
                            if let error = authViewModel.errorMessage, !error.contains("sent") {
                                showingError = true
                            } else {
                                showingSuccess = true
                            }
                        }
                    }) {
                        Text("Send Reset Link")
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
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(authViewModel.errorMessage ?? "Password reset email sent. Check your inbox.")
        }
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthViewModel())
}

