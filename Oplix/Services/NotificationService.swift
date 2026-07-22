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
    /// True after this device’s FCM token was saved under `users/{uid}/fcmTokens`.
    @Published private(set) var hasPersistedToken = false
    /// True while Enable / refresh is waiting on APNs + FCM.
    @Published private(set) var isRegisteringDevice = false
    /// User-visible reason when registration can’t finish (APNs failure, etc.).
    @Published private(set) var registrationMessage: String?

    /// Push can reach the lock screen only when iOS allows alerts and we saved a token.
    var canDeliverOutsideApp: Bool {
        (authStatus == .authorized || authStatus == .provisional) && hasPersistedToken
    }

    // MARK: - Internal state

    /// Most recent FCM token Firebase has handed us. Cached so we
    /// can persist it the moment a user signs in even if Firebase
    /// minted it pre-auth.
    private var cachedToken: String?

    /// User ID we last persisted a token for. Used to avoid
    /// redundant writes on every token-refresh callback when the
    /// signed-in user hasn't changed.
    private var lastPersistedUserId: String?

    /// Set once APNs hands us a device token and we bridge it to FCM.
    /// FCM tokens minted before this hand-off can fail lock-screen delivery.
    private var apnsTokenReady = false

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
        guard apnsTokenReady, let userId = Auth.auth().currentUser?.uid else { return }
        persistToken(token, for: userId)
    }

    /// Called from AppDelegate after `Messaging.messaging().apnsToken` is set.
    /// Re-persists the FCM token for the signed-in user so employee-first
    /// installs don't keep a pre-APNs token that never delivers alerts.
    func noteAPNsTokenReceived() {
        apnsTokenReady = true
        registrationMessage = nil
        guard Auth.auth().currentUser?.uid != nil else { return }
        Task { await refreshAndPersistFCMToken() }
    }

    /// Called from AppDelegate when APNs registration fails (simulator,
    /// missing push entitlement, etc.). Surfaces a reason in Settings.
    func noteAPNsRegistrationFailed(_ error: Error) {
        apnsTokenReady = false
        registrationMessage =
            "Apple push registration failed: \(error.localizedDescription). " +
            "Use a real iPhone (not Simulator) and confirm Push is enabled for the app."
    }

    /// Called after the user signs in. Persists any cached FCM token,
    /// then fetches a fresh one from Firebase so tokens minted before
    /// notification permission are replaced.
    func registerCurrentUser() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        if apnsTokenReady, let token = cachedToken, let userId = Auth.auth().currentUser?.uid {
            persistToken(token, for: userId)
        }
        Task { await refreshAndPersistFCMToken() }
    }

    /// Call when the user turns push on in Oplix settings. In-app toggles
    /// alone are not enough — iOS permission + a saved FCM token are required
    /// for lock-screen delivery.
    @discardableResult
    func ensurePushDeliveryReady() async -> Bool {
        isRegisteringDevice = true
        registrationMessage = nil
        defer { isRegisteringDevice = false }

        await refreshAuthStatus()
        if authStatus == .notDetermined {
            return await requestAuthorization()
        }
        if authStatus == .denied {
            registrationMessage = "iOS is blocking notifications. Open Settings and allow alerts for Oplix."
            return false
        }
        await refreshAndPersistFCMToken()
        if canDeliverOutsideApp {
            registrationMessage = "This device is registered."
        } else if registrationMessage == nil {
            registrationMessage =
                "Couldn’t finish registering this device. Force-quit Oplix, reopen, and try Enable again."
        }
        return canDeliverOutsideApp
    }

    /// Pull the current FCM token from Firebase and save it for the
    /// signed-in user. Call after sign-in, after permission grant,
    /// and when returning to the foreground.
    func refreshAndPersistFCMToken() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        await refreshAuthStatus()
        UIApplication.shared.registerForRemoteNotifications()

        // FCM may already hold the APNs token even if our flag was never set
        // (race on launch / Enable tapped before didRegister callback).
        if !apnsTokenReady, Messaging.messaging().apnsToken != nil {
            apnsTokenReady = true
        }

        // Wait briefly for the APNs callback — previously Enable returned
        // immediately when the flag was still false, so the button looked dead.
        if !apnsTokenReady {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Messaging.messaging().apnsToken != nil {
                    apnsTokenReady = true
                    break
                }
            }
        }

        guard apnsTokenReady else {
            if registrationMessage == nil {
                registrationMessage =
                    "Waiting for Apple push token timed out. Force-quit and reopen Oplix, then tap Enable again."
            }
            return
        }

        do {
            let token = try await Messaging.messaging().token()
            cachedToken = token
            await persistTokenAsync(token, for: userId)
        } catch {
            print("⚠️ FCM token fetch failed: \(error.localizedDescription)")
            registrationMessage = "Couldn’t get Firebase push token: \(error.localizedDescription)"
            hasPersistedToken = false
        }
    }

    /// Called on sign-out. Removes the current device's token doc
    /// so future pushes don't go to a phone whose user just logged
    /// out. We deliberately do NOT call `Messaging.deleteToken()` —
    /// that would invalidate the APNs token entirely; we only want
    /// to break the user→device link.
    func unregisterCurrentDevice() async {
        // Fall back to the signed-in uid so manager logout still clears
        // fcmTokens even when persist hadn't finished yet.
        guard let userId = lastPersistedUserId ?? Auth.auth().currentUser?.uid else { return }
        let deviceId = Self.deviceId
        do {
            try await db.collection("users")
                .document(userId)
                .collection("fcmTokens")
                .document(deviceId)
                .delete()
            lastPersistedUserId = nil
            hasPersistedToken = false
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
            if granted {
                // After opt-in, explicitly re-register so APNs hands a token to
                // FirebaseMessaging (especially important for production builds).
                UIApplication.shared.registerForRemoteNotifications()
                await refreshAndPersistFCMToken()
            }
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
        Task { await persistTokenAsync(token, for: userId) }
    }

    private func persistTokenAsync(_ token: String, for userId: String) async {
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
        do {
            try await ref.setData(payload, merge: true)
            lastPersistedUserId = userId
            hasPersistedToken = true
            registrationMessage = nil
        } catch {
            print("⚠️ Failed to persist FCM token: \(error.localizedDescription)")
            hasPersistedToken = false
            registrationMessage = "Couldn’t save device token: \(error.localizedDescription)"
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
