//
//  AuthViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    
    init() {
        checkAuthState()
    }
    
    func checkAuthState() {
        if Auth.auth().currentUser != nil {
            Task {
                await loadCurrentUser()
            }
        }
    }
    
    func loadCurrentUser() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        do {
            currentUser = try await firebaseService.fetchUser(userId: userId)
            isAuthenticated = true
        } catch {
            errorMessage = "Failed to load user: \(error.localizedDescription)"
            try? firebaseService.signOut()
            isAuthenticated = false
        }
        isLoading = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            currentUser = try await firebaseService.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = "Sign in failed: \(error.localizedDescription)"
            isAuthenticated = false
        }
        isLoading = false
    }
    
    func signUp(email: String, password: String, username: String) async {
        isLoading = true
        errorMessage = nil
        do {
            currentUser = try await firebaseService.createUser(
                email: email,
                password: password,
                username: username,
                role: .manager,
                locationId: nil
            )
            isAuthenticated = true
        } catch {
            errorMessage = "Sign up failed: \(error.localizedDescription)"
            isAuthenticated = false
        }
        isLoading = false
    }
    
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await firebaseService.resetPassword(email: email)
            errorMessage = "Password reset email sent. Check your inbox."
        } catch {
            errorMessage = "Failed to send password reset: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func signOut() {
        do {
            try firebaseService.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }
}

