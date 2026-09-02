//
//  NotificationSettingsView.swift
//  Oplix
//
//  Settings screen where users opt into/out of individual
//  notification categories and channels (push vs email). Reads and
//  writes `User.notificationPrefs`. Resolves nil/missing values to
//  their defaults (everything on except `dailyDigest`) so existing
//  users see a sensible state without needing a one-off migration.
//
//  Layout:
//    1. Channels (push, email) — transport masters
//    2. Categories — per-event-type opt-outs
//    3. Quiet hours — push-only window where notifications are held
//    4. iOS-level escape hatch banner if push permission is denied
//

import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local editing state (snapshotted from prefs on appear)

    @State private var pushEnabled: Bool = true
    @State private var emailEnabled: Bool = true

    @State private var tasksEnabled: Bool = true
    @State private var scheduleEnabled: Bool = true
    @State private var assignmentEnabled: Bool = true
    @State private var shiftSummaryEnabled: Bool = true
    @State private var cashAlertEnabled: Bool = true
    @State private var financeAlertEnabled: Bool = true
    @State private var complianceAlertEnabled: Bool = true
    @State private var dueReminderEnabled: Bool = true
    @State private var dailyDigestEnabled: Bool = false

    @State private var quietHoursEnabled: Bool = false
    @State private var quietStart: Date = Self.dateFromMinutes(22 * 60)
    @State private var quietEnd: Date = Self.dateFromMinutes(7 * 60)

    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var hasLoaded: Bool = false

    private var isManagerLike: Bool {
        guard let role = authViewModel.currentUser?.role else { return false }
        return role == .manager || role == .supervisor
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient.ignoresSafeArea()

            Form {
                if !notificationService.canDeliverOutsideApp {
                    pushDeliveryStatusBanner
                }

                if notificationService.authStatus == .denied {
                    iOSPushDeniedBanner
                }

                Section {
                    Toggle("Push notifications", isOn: $pushEnabled)
                        .onChange(of: pushEnabled) { _, newValue in
                            if newValue {
                                Task { await notificationService.ensurePushDeliveryReady() }
                            }
                            scheduleSave()
                        }
                    Toggle("Email notifications", isOn: $emailEnabled)
                        .onChange(of: emailEnabled) { _, _ in scheduleSave() }
                } header: {
                    Text("How")
                } footer: {
                    Text("Turn a channel off to silence every notification on that channel without losing your category preferences.")
                }

                Section {
                    Toggle("Task updates", isOn: $tasksEnabled)
                        .onChange(of: tasksEnabled) { _, _ in scheduleSave() }
                    Toggle("Schedule changes", isOn: $scheduleEnabled)
                        .onChange(of: scheduleEnabled) { _, _ in scheduleSave() }
                    Toggle("Location & role changes", isOn: $assignmentEnabled)
                        .onChange(of: assignmentEnabled) { _, _ in scheduleSave() }
                    Toggle("Shift end summary (email)", isOn: $shiftSummaryEnabled)
                        .onChange(of: shiftSummaryEnabled) { _, _ in scheduleSave() }

                    if isManagerLike {
                        Toggle("Cash variance alert", isOn: $cashAlertEnabled)
                            .onChange(of: cashAlertEnabled) { _, _ in scheduleSave() }
                        Toggle("Overdue payables & receivables", isOn: $financeAlertEnabled)
                            .onChange(of: financeAlertEnabled) { _, _ in scheduleSave() }
                        Toggle("Compliance & license expiry", isOn: $complianceAlertEnabled)
                            .onChange(of: complianceAlertEnabled) { _, _ in scheduleSave() }
                        Toggle("Due date reminders", isOn: $dueReminderEnabled)
                            .onChange(of: dueReminderEnabled) { _, _ in scheduleSave() }
                        Toggle("Daily digest (email)", isOn: $dailyDigestEnabled)
                            .onChange(of: dailyDigestEnabled) { _, _ in scheduleSave() }
                    }
                } header: {
                    Text("What")
                } footer: {
                    Text("A notification only goes out when both the channel and the matching category are on.")
                }

                Section {
                    Toggle("Pause push during quiet hours", isOn: $quietHoursEnabled)
                        .onChange(of: quietHoursEnabled) { _, _ in scheduleSave() }
                    if quietHoursEnabled {
                        DatePicker("Start", selection: $quietStart, displayedComponents: .hourAndMinute)
                            .onChange(of: quietStart) { _, _ in scheduleSave() }
                        DatePicker("End", selection: $quietEnd, displayedComponents: .hourAndMinute)
                            .onChange(of: quietEnd) { _, _ in scheduleSave() }
                    }
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("Push notifications are held silently while quiet hours are active. Email is unaffected.")
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .task {
            await notificationService.refreshAuthStatus()
            if pushEnabled {
                await notificationService.ensurePushDeliveryReady()
            }
            if !hasLoaded {
                loadFromUser()
                hasLoaded = true
            }
        }
    }

    // MARK: - Delivery status (in-app prefs vs lock-screen push)

    private var pushDeliveryStatusBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundColor(.orange)
                    Text("Lock-screen delivery")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                }

                Text(deliveryStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let registrationMessage = notificationService.registrationMessage,
                   !notificationService.canDeliverOutsideApp {
                    Text(registrationMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if notificationService.authStatus != .denied {
                    Button {
                        Task { await notificationService.ensurePushDeliveryReady() }
                    } label: {
                        HStack(spacing: 8) {
                            if notificationService.isRegisteringDevice {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(notificationService.isRegisteringDevice
                                  ? "Registering…"
                                  : "Enable iOS notifications")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.cloudBlue)
                    .disabled(notificationService.isRegisteringDevice)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var deliveryStatusMessage: String {
        switch notificationService.authStatus {
        case .authorized:
            if notificationService.hasPersistedToken {
                return "This device is registered. You should get alerts when the app is closed."
            }
            return "iOS allows notifications, but this device isn’t registered yet. Tap Enable below, then reopen the app."
        case .denied:
            return "Oplix preferences are on, but iOS is blocking alerts. Use Open Settings below."
        case .notDetermined:
            return "Oplix preferences are on, but iOS hasn’t been asked yet. Tap Enable below."
        default:
            return "Turn on iOS notifications to get task alerts outside the app."
        }
    }

    // MARK: - iOS-level "push off" banner

    private var iOSPushDeniedBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.orange)
                    Text("Push is off in iOS Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                }
                Text("Even with push enabled here, iOS will block notifications until you re-enable them in the system Settings app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.cloudBlue)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Load + save helpers

    private func loadFromUser() {
        guard let prefs = authViewModel.currentUser?.notificationPrefs else {
            // Defaults already in place via @State initial values.
            return
        }
        if let channels = prefs.channels {
            pushEnabled = channels.resolvedPush
            emailEnabled = channels.resolvedEmail
        }
        if let categories = prefs.categories {
            tasksEnabled = categories.resolvedTasks
            scheduleEnabled = categories.resolvedSchedule
            assignmentEnabled = categories.resolvedAssignment
            shiftSummaryEnabled = categories.resolvedShiftSummary
            cashAlertEnabled = categories.resolvedCashAlert
            financeAlertEnabled = categories.resolvedFinanceAlert
            complianceAlertEnabled = categories.resolvedComplianceAlert
            dueReminderEnabled = categories.resolvedDueReminder
            dailyDigestEnabled = categories.resolvedDailyDigest
        }
        if let quiet = prefs.quietHours {
            quietHoursEnabled = quiet.resolvedEnabled
            quietStart = Self.dateFromMinutes(quiet.resolvedStartMin)
            quietEnd = Self.dateFromMinutes(quiet.resolvedEndMin)
        }
    }

    /// Debounce-of-1: cancel any pending save and queue a new one
    /// after a short delay. Toggling several rows quickly results in
    /// a single network write rather than one per toggle.
    @State private var pendingSaveTask: Task<Void, Never>?

    private func scheduleSave() {
        guard hasLoaded else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350 ms
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        let prefs = NotificationPrefs(
            channels: NotificationPrefs.Channels(
                push: pushEnabled,
                email: emailEnabled
            ),
            categories: NotificationPrefs.Categories(
                tasks: tasksEnabled,
                schedule: scheduleEnabled,
                assignment: assignmentEnabled,
                shiftSummary: shiftSummaryEnabled,
                cashAlert: cashAlertEnabled,
                financeAlert: financeAlertEnabled,
                complianceAlert: complianceAlertEnabled,
                dueReminder: dueReminderEnabled,
                dailyDigest: dailyDigestEnabled
            ),
            quietHours: NotificationPrefs.QuietHours(
                enabled: quietHoursEnabled,
                startMin: Self.minutesFromDate(quietStart),
                endMin: Self.minutesFromDate(quietEnd)
            )
        )
        isSaving = true
        defer { isSaving = false }
        do {
            try await authViewModel.updateNotificationPrefs(prefs)
            saveError = nil
        } catch {
            saveError = "Couldn't save preferences: \(error.localizedDescription)"
        }
    }

    // MARK: - Time conversion (minutes ↔ Date)

    private static func dateFromMinutes(_ minutes: Int) -> Date {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environmentObject(AuthViewModel())
    }
}
