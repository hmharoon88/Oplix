//
//  RoleSelectionView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var selectedRole: User.UserRole = .manager
    @State private var identity = ""
    @State private var password = ""
    @State private var showingError = false
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @State private var showingResendVerification = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var isExecutive: Bool { selectedRole == .manager }

    private var accentColor: Color {
        switch selectedRole {
        case .manager: return Theme.cloudBlue
        case .supervisor: return Color.purple
        case .employee: return Theme.sunshineYellow
        }
    }

    private var canSubmit: Bool {
        let id = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !password.isEmpty else { return false }
        return !authViewModel.isLoading
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.3, blue: 0.6),
                    Color(red: 0.15, green: 0.4, blue: 0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        Spacer(minLength: 0)

                        VStack(spacing: 10) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.white)

                            Text("Oplix")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)

                            Text("Operation Link")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.85))

                            Text("Cloud-Based Management")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.92))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign in as")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.85))

                            Picker("Role", selection: $selectedRole) {
                                Text("Executive").tag(User.UserRole.manager)
                                Text("Supervisor").tag(User.UserRole.supervisor)
                                Text("Team Member").tag(User.UserRole.employee)
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.regular)
                            .oplixSegmentedPickerTint()

                            VStack(alignment: .leading, spacing: 10) {
                                Group {
                                    if isExecutive {
                                        TextField("Email", text: $identity)
                                            .textContentType(.username)
                                            .keyboardType(.emailAddress)
                                            .textInputAutocapitalization(.never)
                                    } else {
                                        TextField("Username", text: $identity)
                                            .textContentType(.username)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }
                                }
                                .oplixCompactFormField()

                                SecureField("Password", text: $password)
                                    .oplixCompactFormField()

                                if !isExecutive {
                                    Text("You'll sign in as \(identityTrimmedForCaption)@oplix.app")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button(action: { Task { await performSignIn() } }) {
                                Text("Sign In")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(selectedRole == .employee ? Color.black : Color.white)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(accentColor)
                                    )
                                    .shadow(color: accentColor.opacity(0.35), radius: 5, x: 0, y: 2)
                            }
                            .disabled(!canSubmit)

                            if isExecutive {
                                VStack(spacing: 10) {
                                    Button("Forgot Password?") {
                                        showingForgotPassword = true
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.62))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.primary.opacity(0.05))
                                    )

                                    Button("Don't have an account? Sign Up") {
                                        showingSignUp = true
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Theme.cloudBlue)
                                    )
                                }
                                .padding(.top, 2)
                            }
                        }
                        .oplixCompactGlassCard(maxWidth: 380)
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text("Version \(appVersion)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.top, 4)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .onChange(of: selectedRole) { _, _ in
            identity = ""
            password = ""
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authViewModel.errorMessage ?? "Unknown error")
        }
        .alert("Email Verification Required", isPresented: $showingResendVerification) {
            Button("Resend Verification Email") {
                Task { @MainActor in
                    let email = identity.trimmingCharacters(in: .whitespacesAndNewlines)
                    let success = await authViewModel.resendVerificationEmail(email: email, password: password)
                    if success {
                        showingResendVerification = false
                        showingError = true
                        authViewModel.errorMessage =
                            "Verification email resent! Please check your inbox (and spam folder) and click the verification link."
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

    private var identityTrimmedForCaption: String {
        let t = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "username" : t
    }

    @MainActor
    private func performSignIn() async {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let email: String
        switch selectedRole {
        case .manager:
            email = trimmed
        case .supervisor, .employee:
            email = "\(trimmed)@oplix.app"
        }

        await authViewModel.signIn(email: email, password: password)

        if authViewModel.errorMessage != nil {
            if isExecutive, authViewModel.errorMessage?.contains("verify your email") == true {
                showingResendVerification = true
            } else {
                showingError = true
            }
        }
    }
}

#Preview {
    RoleSelectionView()
        .environmentObject(AuthViewModel())
}
