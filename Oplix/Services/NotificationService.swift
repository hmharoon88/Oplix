//
//  NotificationService.swift
//  Oplix
//
//  Push notification orchestration: token capture, per-device
//  persistence on the user's Firestore doc, and permission UX.
//
//  The service is deliberately small and stateful — it's the only
//  place in the app that knows about FCM tokens, so the rest of the
//  codebase doesn't have to care.
//
//  Storage shape (purely additive — does not touch existing fields):
//
//    users/{userId}/fcmTokens/{deviceId}
//      └── token: String
//          platform: "ios"
//          appVersion: String
//          updatedAt: Timestamp
//
//  Why per-device subcollection (not a single field on users/{userId}):
//    - Multi-device support out of the box (employee with iPhone + iPad)
//    - Stale token cleanup is just a doc delete, not a string-array splice
//    - Cloud Functions enumerate `fcmTokens` to fan-out to all devices
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    // MARK: - Public state observable by SwiftUI
    //
    // `authStatus` reflects the iOS-level permission. The Settings
    // UI uses this to show "Push notifications are turned off in iOS
    // Settings" if the user denied earlier and never came back.
    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Internal state

    /// Most recent FCM token Firebase has handed us. Cached so we
    /// can persist it the moment a user signs in even if Firebase
    /// minted it pre-auth.
    private var cachedToken: String?

    /// User ID we last persisted a token for. Used to avoid
    /// redundant writes on every token-refresh callback when the
    /// signed-in user hasn't changed.
    private var lastPersistedUserId: String?

    private let db = Firestore.firestore()

    private init() {
        Task { await refreshAuthStatus() }
    }

    // MARK: - Public API

    /// Called from `MessagingDelegate.didReceiveRegistrationToken`
    /// when Firebase issues us a token. We cache it and try to
    /// persist immediately; if no user is signed in yet, the cached
    /// token gets persisted by `registerCurrentUser()` post-sign-in.
    func handleFCMToken(_ token: String) {
        cachedToken = token
        if let userId = Auth.auth().currentUser?.uid {
            persistToken(token, for: userId)
        }
    }

    /// Called after the user signs in. Persists any cached FCM
    /// token onto their user doc so Cloud Functions can target them.
    /// Safe to call repeatedly — the `lastPersistedUserId` guard
    /// keeps it idempotent.
    func registerCurrentUser() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard userId != lastPersistedUserId else { return }
        if let token = cachedToken {
            persistToken(token, for: userId)
        }
    }

    /// Called on sign-out. Removes the current device's token doc
    /// so future pushes don't go to a phone whose user just logged
    /// out. We deliberately do NOT call `Messaging.deleteToken()` —
    /// that would invalidate the APNs token entirely; we only want
    /// to break the user→device link.
    func unregisterCurrentDevice() async {
        guard let userId = lastPersistedUserId else { return }
        let deviceId = Self.deviceId
        do {
            try await db.collection("users")
                .document(userId)
                .collection("fcmTokens")
                .document(deviceId)
                .delete()
            lastPersistedUserId = nil
        } catch {
            print("⚠️ Failed to unregister device token: \(error.localizedDescription)")
        }
    }

    /// Ask iOS for permission. Should be invoked **after** the user
    /// has seen the in-app explainer (NotificationPermissionView)
    /// so the cold prompt doesn't surprise them and tank opt-in.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthStatus()
            return granted
        } catch {
            print("⚠️ requestAuthorization failed: \(error.localizedDescription)")
            await refreshAuthStatus()
            return false
        }
    }

    /// Re-pull current authorization status from iOS. Called on
    /// init, after permission requests, and on app foreground.
    func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authStatus = settings.authorizationStatus
    }

    /// Tap-handling stub — real deep-link routing lands in Step 3
    /// when we know the data payload shapes. For now we just log so
    /// the AppDelegate hook compiles cleanly.
    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("📬 Notification tapped, payload: \(userInfo)")
        // TODO(step 3+): dispatch to a TabRouter / NavigationPath
        //                based on `userInfo["category"]`.
    }

    // MARK: - Persistence

    private func persistToken(_ token: String, for userId: String) {
        let deviceId = Self.deviceId
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let payload: [String: Any] = [
            "token": token,
            "platform": "ios",
            "appVersion": appVersion,
            "updatedAt": FieldValue.serverTimestamp(),
        ]

        let ref = db.collection("users")
            .document(userId)
            .collection("fcmTokens")
            .document(deviceId)

        // Use setData(merge: true) so re-running on the same device
        // updates the same doc (no proliferation of dead tokens) and
        // so we can later add fields like `notificationPrefs` cache
        // without clobbering this one.
        ref.setData(payload, merge: true) { [weak self] error in
            if let error = error {
                print("⚠️ Failed to persist FCM token: \(error.localizedDescription)")
                return
            }
            self?.lastPersistedUserId = userId
        }
    }

    /// Stable per-device identifier used as the doc id under
    /// `fcmTokens/{deviceId}`. UIDevice.identifierForVendor is
    /// stable across launches for this vendor's apps and resets on
    /// uninstall — exactly what we want for "one doc per physical
    /// device". Falls back to a random UUID stored in UserDefaults
    /// only if iOS denies the vendor id (which it shouldn't).
    private static var deviceId: String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        let key = "oplix.fallbackDeviceId"
        if let cached = UserDefaults.standard.string(forKey: key) { return cached }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
