//
//  LocationNotificationSettingsView.swift
//  Oplix
//
//  Per-facility Needs Attention configuration — parity with web Customize → Notifications.
//

import SwiftUI

struct LocationNotificationSettingsView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var settings = FacilityNotificationSettings()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var groups: [String] {
        var ordered: [String] = []
        for type in FacilityNotificationType.allCases where !ordered.contains(type.group) {
            ordered.append(type.group)
        }
        return ordered
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            Form {
                Section {
                    Text("Choose which alerts appear under Needs Attention and as push notifications for this facility.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(FacilityNotificationType.allCases.filter { $0.group == group }) { type in
                            notificationRow(for: type)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                }
            }
        }
        .onAppear {
            settings = viewModel.location?.effectiveNotificationSettings ?? FacilityNotificationSettings.normalized(nil)
        }
    }

    @ViewBuilder
    private func notificationRow(for type: FacilityNotificationType) -> some View {
        let binding = Binding(
            get: { settings.isEnabled(type) },
            set: { newValue in
                var copy = settings
                copy.setEnabled(type, enabled: newValue)
                settings = copy
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            Toggle(type.label, isOn: binding)

            if type.hasLeadDays, settings.isEnabled(type) {
                Stepper(
                    value: leadDaysBinding(for: type),
                    in: 0...365
                ) {
                    Text("Lead time: \(settings.leadDays(for: type) ?? type.defaultLeadDays) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func leadDaysBinding(for type: FacilityNotificationType) -> Binding<Int> {
        Binding(
            get: { settings.leadDays(for: type) ?? type.defaultLeadDays },
            set: { newValue in
                var copy = settings
                copy.setLeadDays(type, days: newValue)
                settings = copy
            }
        )
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await viewModel.updateNotificationSettings(settings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
