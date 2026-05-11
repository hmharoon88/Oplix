//
//  OplixApp.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct OplixApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .preferredColorScheme(.light) // Force light mode for consistent colors
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated, let user = authViewModel.currentUser {
                if user.role == .manager {
                    ManagerDashboardView()
                } else {
                    EmployeeHomeView(user: user)
                }
            } else {
                RoleSelectionView()
            }
        }
        .task(id: authViewModel.isAuthenticated) {
            // Only load if not already authenticated and user exists
            if !authViewModel.isAuthenticated && Auth.auth().currentUser != nil {
                await authViewModel.loadCurrentUser()
            }
        }
    }
}
