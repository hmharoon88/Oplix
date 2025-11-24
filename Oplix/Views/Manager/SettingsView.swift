//
//  SettingsView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingLogoutConfirmation = false
    @State private var organizationName: String = ""
    @State private var showingAbout = false
    @State private var showingDeleteAccount = false
    @State private var isSavingOrganizationName = false
    @State private var showingSaveSuccess = false
    @State private var saveErrorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header with App Logo
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                        Text("Settings")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                                Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Content Area
                    List {
                        Section("Organization") {
                            HStack {
                                Text("Organization Name")
                                Spacer()
                                TextField("Enter organization name", text: $organizationName)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.secondary)
                                    .disabled(isSavingOrganizationName)
                            }
                            
                            if isSavingOrganizationName {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            } else if !organizationName.isEmpty {
                                Button("Save") {
                                    Task {
                                        await saveOrganizationName()
                                    }
                                }
                                .foregroundColor(Theme.cloudBlue)
                            }
                        }
                        
                        Section("Account") {
                            if let user = authViewModel.currentUser {
                                HStack {
                                    Text("Username")
                                    Spacer()
                                    Text(user.username)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text("Role")
                                    Spacer()
                                    Text(user.role.rawValue.capitalized)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Section("Information") {
                            Button(action: {
                                showingAbout = true
                            }) {
                                HStack {
                                    Image(systemName: "info.circle")
                                    Text("About")
                                }
                            }
                        }
                        
                        Section("Actions") {
                            Button(role: .destructive, action: {
                                showingLogoutConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.right.square")
                                    Text("Logout")
                                }
                            }
                            
                            Button(role: .destructive, action: {
                                showingDeleteAccount = true
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Account")
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    
                    // Colored Footer
                    HStack {
                        Spacer()
                        Text("© 2025 Oplix")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                                Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                organizationName = authViewModel.currentUser?.organizationName ?? ""
            }
            .alert("Logout", isPresented: $showingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    authViewModel.signOut()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
            .alert("Success", isPresented: $showingSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Organization name saved successfully")
            }
            .alert("Error", isPresented: .constant(saveErrorMessage != nil)) {
                Button("OK", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                if let error = saveErrorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingDeleteAccount) {
                if let user = authViewModel.currentUser {
                    DeleteAccountView(user: user, authViewModel: authViewModel)
                }
            }
        }
    }
    
    private func saveOrganizationName() async {
        guard var user = authViewModel.currentUser else { return }
        isSavingOrganizationName = true
        saveErrorMessage = nil
        
        do {
            user.organizationName = organizationName.isEmpty ? nil : organizationName
            try await authViewModel.updateUser(user)
            showingSaveSuccess = true
        } catch {
            saveErrorMessage = "Failed to save organization name: \(error.localizedDescription)"
        }
        
        isSavingOrganizationName = false
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // App Version
                        VStack(alignment: .leading, spacing: 8) {
                            Text("App Version")
                                .font(.headline)
                                .foregroundColor(.black)
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.cloudBlue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        
                        // App Description
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About Oplix")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            Text("Oplix is a comprehensive cloud-based workforce management application designed for managers and employees.")
                                .font(.body)
                                .foregroundColor(.black)
                            
                            Text("Key Features:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .padding(.top, 8)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                FeatureRow(icon: "building.2.fill", text: "Location Management - Create and manage multiple business locations")
                                FeatureRow(icon: "person.2.fill", text: "Employee Management - Add employees, assign schedules, and set permissions")
                                FeatureRow(icon: "checklist", text: "Task Management - Create tasks and track completion with photo verification")
                                FeatureRow(icon: "clock.fill", text: "Shift Management - Track employee hours, clock in/out, and payroll")
                                FeatureRow(icon: "dollarsign.circle.fill", text: "Payroll & Sales - Calculate weekly payroll and track daily sales/expenses")
                                FeatureRow(icon: "cashregister.fill", text: "Register Data - Employees can enter shift register data and expenses")
                                FeatureRow(icon: "ticket.fill", text: "Lottery Forms - Submit and track lottery forms")
                            }
                            .padding(.leading, 8)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    }
                    .padding()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.cloudBlue)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundColor(.black)
            Spacer()
        }
    }
}

struct DeleteAccountView: View {
    let user: User
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var password: String = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSuccess = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        Text("⚠️ Warning: This action cannot be undone!")
                            .font(.headline)
                            .foregroundColor(.red)
                    } header: {
                        Text("Delete Account")
                    } footer: {
                        Text("Deleting your account will permanently remove all your data including locations, employees, tasks, shifts, and all associated information. All employee credentials will also be deleted. An email will be sent to your registered email address.")
                    }
                    
                    Section("Confirm Password") {
                        SecureField("Enter your password", text: $password)
                    }
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete") {
                        Task {
                            await deleteAccount()
                        }
                    }
                    .disabled(password.isEmpty || isDeleting)
                    .foregroundColor(.red)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .alert("Account Deleted", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your account and all associated data have been permanently deleted.")
            }
        }
    }
    
    private func deleteAccount() async {
        guard !password.isEmpty else {
            errorMessage = "Please enter your password"
            showingError = true
            return
        }
        
        isDeleting = true
        errorMessage = nil
        
        do {
            try await authViewModel.deleteAccount(password: password)
            showingSuccess = true
            // Dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isDeleting = false
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
