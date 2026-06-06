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
                
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.white)
                    
                    Text("Supervisor Login")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 12) {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                        .oplixCompactFormField()
                    
                    SecureField("Password", text: $password)
                        .oplixCompactFormField()
                    
                    Text("Login as: \(username.isEmpty ? "username" : username)@oplix.app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
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
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Color.purple)
                            .cornerRadius(11)
                            .shadow(color: Color.purple.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(authViewModel.isLoading || username.isEmpty)
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
    }
}

#Preview {
    SupervisorLoginView()
        .environmentObject(AuthViewModel())
}

