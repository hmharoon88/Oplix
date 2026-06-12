//
//  OplixApp.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import UserNotifications

/// App delegate. Owns Firebase configure + the APNs/FCM token bridge.
///
/// Why we need both `MessagingDelegate` and `UNUserNotificationCenterDelegate`:
///   - APNs hands us a device token (`didRegisterForRemoteNotificationsWithDeviceToken`)
///     which we forward to FirebaseMessaging — without that hand-off FCM
///     can't mint an FCM token and `messaging.token` stays nil.
///   - `UNUserNotificationCenterDelegate` lets us decide how
///     foreground notifications render (banner + sound) and gives
///     us a hook for handling taps for deep linking later.
///   - `MessagingDelegate` is how Firebase tells us the FCM token
///     refreshed — we forward it to `NotificationService` which
///     persists it on the user's Firestore doc.
///
/// We deliberately do NOT call `requestAuthorization` here. The
/// permission prompt is triggered later by `NotificationService`
/// after the user signs in and has had a chance to see the in-app
/// explainer, so opt-in rates aren't tanked by a cold-start prompt.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Wire up Firebase Messaging token + foreground display.
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // Always register with APNs on launch — even before we've
        // asked for permission. This makes the APNs device token
        // available to FCM, which lets the app receive *silent*
        // (data-only) pushes and lets us mint an FCM token early.
        // Visible alerts/banners still require the explicit
        // `requestAuthorization` flow that runs after sign-in.
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - APNs token bridge → FirebaseMessaging
    //
    // Without this hand-off, FCM has no transport and
    // `Messaging.messaging().token` will never resolve.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Most common cause in dev: running on Simulator (which can't
        // get a real APNs token) or the entitlement missing in the
        // signing profile. Logged but non-fatal — the app still works,
        // just won't receive push.
        print("⚠️ APNs registration failed: \(error.localizedDescription)")
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    /// Called whenever Firebase mints a new FCM token for this device
    /// (first launch, app reinstall, restored from backup, etc). We
    /// forward to `NotificationService` which writes it to the user
    /// doc — but only if a user is signed in. If nobody's signed in
    /// yet the token is held in-memory and persisted right after sign-in.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationService.shared.handleFCMToken(token)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show banners + play sounds even when the app is foreground.
    /// Without this, foreground notifications are silently dropped
    /// (default iOS behaviour) which makes "I'm in the app and just
    /// got assigned a task" feel broken.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Hook for tap → deep-link routing. We extract the `data`
    /// payload Firebase forwards from the Cloud Function and hand
    /// it to `NotificationService` which decides which screen to
    /// route to. (Routing logic lands in Step 3 with the first
    /// real notification type — for now we just record the tap.)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        NotificationService.shared.handleNotificationTap(userInfo: userInfo)
        completionHandler()
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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var showingNotificationPreprompt = false

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

            // Push notification lifecycle hooks. We piggy-back on the
            // same task that already reacts to auth changes:
            //   - On sign-in: persist any cached FCM token to the
            //     user's `fcmTokens/{deviceId}` doc, then check if
            //     this device has ever seen the explainer; if not,
            //     queue it up to present.
            //   - On sign-out: detach this device from the previous
            //     user so future pushes don't go to the wrong inbox.
            if authViewModel.isAuthenticated {
                notificationService.registerCurrentUser()
                await notificationService.refreshAuthStatus()
                if notificationService.authStatus == .authorized {
                    await notificationService.refreshAndPersistFCMToken()
                } else if notificationService.authStatus == .notDetermined,
                          !UserDefaults.standard.bool(forKey: NotificationPermissionView.didShowPrepromptKey) {
                    showingNotificationPreprompt = true
                }
            } else {
                await notificationService.unregisterCurrentDevice()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, authViewModel.isAuthenticated else { return }
            Task { await notificationService.refreshAndPersistFCMToken() }
        }
        .sheet(isPresented: $showingNotificationPreprompt) {
            NotificationPermissionView()
                .interactiveDismissDisabled(false)
        }
    }
}
