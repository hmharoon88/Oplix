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
    private var isLoadCurrentUserInProgress = false // Prevent concurrent calls
    private var hasLoadedCurrentUser = false // Track if user has been loaded
    
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
        // Prevent concurrent calls
        guard !isLoadCurrentUserInProgress else {
            print("⚠️ loadCurrentUser already in progress, skipping...")
            return
        }
        
        // If user is already loaded and authenticated, don't reload
        if hasLoadedCurrentUser && isAuthenticated && currentUser != nil {
            print("⚠️ loadCurrentUser skipped - user already loaded: \(currentUser?.id ?? "nil")")
            return
        }
        
        // Don't load if already logged out
        guard isAuthenticated || Auth.auth().currentUser != nil else {
            print("⚠️ loadCurrentUser skipped - user not authenticated")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else {
            isAuthenticated = false
            currentUser = nil
            hasLoadedCurrentUser = false
            return
        }
        
        isLoadCurrentUserInProgress = true
        isLoading = true
        do {
            currentUser = try await firebaseService.fetchUser(userId: userId)
            isAuthenticated = true
            hasLoadedCurrentUser = true
        } catch {
            print("🔴 Error loading current user: \(error.localizedDescription)")
            errorMessage = "Failed to load user: \(error.localizedDescription)"
            try? firebaseService.signOut()
            isAuthenticated = false
            currentUser = nil
            hasLoadedCurrentUser = false
        }
        isLoading = false
        isLoadCurrentUserInProgress = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            currentUser = try await firebaseService.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticated = false
        }
        isLoading = false
    }
    
    func signUp(email: String, password: String, username: String, role: User.UserRole = .manager) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await firebaseService.createUser(
                email: email,
                password: password,
                username: username,
                role: role,
                locationId: nil
            )
            // Don't authenticate - user needs to verify email first
            isAuthenticated = false
            isLoading = false
            return true // Success - email verification sent
        } catch {
            errorMessage = "Sign up failed: \(error.localizedDescription)"
            isAuthenticated = false
            isLoading = false
            return false
        }
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
    
    func resendVerificationEmail(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            try await firebaseService.resendEmailVerification(email: email, password: password)
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    func signOut() {
        do {
            // Stop all listeners before signing out
            firebaseService.removeAllListeners()
            try firebaseService.signOut()
            currentUser = nil
            isAuthenticated = false
            errorMessage = nil
            isLoading = false
            hasLoadedCurrentUser = false // Reset flag on logout
            isLoadCurrentUserInProgress = false
        } catch {
            errorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }
    
    func updateUser(_ user: User) async throws {
        let userId = user.id
        try await firebaseService.updateUser(userId: userId, user: user)
        currentUser = user
    }

    /// Persist a new `notificationPrefs` value for the signed-in user.
    /// Touches only the `notificationPrefs` map on Firestore (via
    /// `updateNotificationPrefs`) so no other User fields are at risk
    /// of being clobbered by a stale local copy.
    func updateNotificationPrefs(_ prefs: NotificationPrefs) async throws {
        guard var user = currentUser else { return }
        try await firebaseService.updateNotificationPrefs(userId: user.id, prefs: prefs)
        user.notificationPrefs = prefs
        currentUser = user
    }

    /// Dismiss a Needs Attention alert from Home / Location screens.
    func acknowledgeAlert(_ alertId: String) async {
        guard var user = currentUser else { return }
        guard !user.resolvedAcknowledgedAlertIds.contains(alertId) else { return }
        do {
            try await firebaseService.acknowledgeAlert(userId: user.id, alertId: alertId)
            var ids = user.resolvedAcknowledgedAlertIds
            ids.append(alertId)
            user.acknowledgedAlertIds = ids
            currentUser = user
        } catch {
            print("🔴 Failed to acknowledge alert: \(error.localizedDescription)")
        }
    }

    var acknowledgedAlertIdSet: Set<String> {
        Set(currentUser?.resolvedAcknowledgedAlertIds ?? [])
    }
    
    func deleteAccount(password: String) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "AuthViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        try await firebaseService.deleteAccount(userId: userId, password: password)
        currentUser = nil
        isAuthenticated = false
    }
}

