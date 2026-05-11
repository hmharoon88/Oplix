//
//  NotificationPermissionView.swift
//  Oplix
//
//  Friendly pre-prompt sheet shown after the user signs in for the
//  first time. Explains what we'll send before iOS pops its
//  one-shot system permission prompt — that pre-explanation is the
//  single biggest factor in opt-in rate. Once the user makes a
//  choice (Enable or "Maybe later") we set a UserDefaults flag and
//  never show the sheet again on this device. Users can always come
//  back via Settings → Notifications (Step 2) to flip individual
//  preferences if they did opt in.
//

import SwiftUI

struct NotificationPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var isRequesting = false

    /// One-shot defaults flag: once set, this sheet never shows
    /// again automatically. Cleared by sign-out so users on a
    /// shared device aren't denied the explainer on each login.
    static let didShowPrepromptKey = "oplix.notifications.didShowPreprompt"

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                Text("Stay in the loop")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("We'll let you know about the things that actually matter.")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 14) {
                    bullet(icon: "checklist", text: "When a task is assigned to you")
                    bullet(icon: "checkmark.seal", text: "When your work is approved or sent back")
                    bullet(icon: "calendar", text: "When your schedule changes")
                    bullet(icon: "mappin.and.ellipse", text: "When your location or role updates")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .background(Color.white.opacity(0.12))
                .cornerRadius(16)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: { Task { await enable() } }) {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Theme.cloudBlue)
                            }
                            Text(isRequesting ? "Enabling…" : "Enable Notifications")
                                .font(.headline)
                        }
                        .foregroundColor(Theme.cloudBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(14)
                    }
                    .disabled(isRequesting)

                    Button(action: { skip() }) {
                        Text("Maybe later")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .disabled(isRequesting)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer(minLength: 0)
        }
    }

    private func enable() async {
        isRequesting = true
        _ = await notificationService.requestAuthorization()
        UserDefaults.standard.set(true, forKey: Self.didShowPrepromptKey)
        isRequesting = false
        dismiss()
    }

    private func skip() {
        // Mark seen — we'll respect their choice and not nag. They
        // can still flip the toggle on later from Settings, which
        // (in Step 2) will deep-link to iOS Settings if iOS itself
        // is the source of the "off" state.
        UserDefaults.standard.set(true, forKey: Self.didShowPrepromptKey)
        dismiss()
    }
}

#Preview {
    NotificationPermissionView()
}
