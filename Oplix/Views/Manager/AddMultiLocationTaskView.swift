//
//  AddMultiLocationTaskView.swift
//  Oplix
//
//  Created on 5/10/26.
//

import SwiftUI

// Sheet for creating a task that applies to one or more locations. Reached
// from Task Check → tap location → Recurring/Corrective section + button →
// "Pick Multiple Locations".
//
// One WorkTask document is written per selected location so each location's
// task list shows the task independently. All siblings share a
// `crossLocationGroupId` so the Edit flow can later propagate description
// or frequency changes across them.
//
// The `frequencyMode` parameter controls which frequencies are allowed:
//   - `.onlyCorrective` → frequency locked to `.oneTime`, no picker shown.
//   - `.onlyRecurring(default:)` → picker showing Daily/Weekly/Monthly with
//                                  the supplied default selected initially.
//   - `.any` → picker covering every frequency (kept for completeness).
//
// Each task is created **unassigned**: assignees vary per location, and the
// manager can assign people from each location's task list afterwards.
struct AddMultiLocationTaskView: View {
    let userId: String
    let allLocations: [Location]
    let preselectedLocationId: String
    var frequencyMode: AddTaskFrequencyMode = .onlyCorrective
    let onSave: ([Location]) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var description = ""
    @State private var selectedLocationIds: Set<String> = []
    @State private var frequency: TaskFrequency = .oneTime
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: - Mode helpers

    private var isCorrectiveOnly: Bool {
        if case .onlyCorrective = frequencyMode { return true }
        return false
    }

    private var allowedFrequencies: [TaskFrequency] {
        switch frequencyMode {
        case .any:
            return TaskFrequency.allCases
        case .onlyRecurring:
            return TaskFrequency.allCases.filter { $0.isRecurring }
        case .onlyCorrective:
            return [.oneTime]
        }
    }

    private var navigationTitleText: String {
        if isCorrectiveOnly { return "New Corrective Task" }
        return "New Recurring Task"
    }

    private var lockedTypeLabel: String {
        if isCorrectiveOnly { return "Corrective Task" }
        return "Recurring Task"
    }

    private var lockedTypeIcon: String {
        if isCorrectiveOnly { return "wrench.and.screwdriver.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private var lockedTypeColor: Color {
        if isCorrectiveOnly { return .orange }
        return Theme.cloudBlue
    }

    private var typeFooter: String {
        if isCorrectiveOnly {
            return "Corrective tasks complete once. The same task will be created at each selected location."
        }
        return "Recurring tasks reset each cycle (daily, weekly, or monthly). The same task will be created at each selected location."
    }

    // MARK: - Selection helpers

    private var allSelected: Bool {
        !allLocations.isEmpty && selectedLocationIds.count == allLocations.count
    }

    private var selectedLocations: [Location] {
        allLocations.filter { selectedLocationIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                Form {
                    Section("Task Details") {
                        TextField("Description", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if isCorrectiveOnly {
                        Section {
                            HStack {
                                Image(systemName: lockedTypeIcon)
                                    .foregroundColor(lockedTypeColor)
                                Text(lockedTypeLabel)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("One-time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } footer: {
                            Text(typeFooter)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Section {
                            HStack {
                                Image(systemName: lockedTypeIcon)
                                    .foregroundColor(lockedTypeColor)
                                Text(lockedTypeLabel)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            Picker("Frequency", selection: $frequency) {
                                ForEach(allowedFrequencies, id: \.self) { freq in
                                    Text(freq.displayName).tag(freq)
                                }
                            }
                        } footer: {
                            Text(typeFooter)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        if allLocations.isEmpty {
                            Text("No locations available.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: toggleSelectAll) {
                                HStack {
                                    Text(allSelected ? "Deselect All" : "Select All")
                                        .foregroundColor(Theme.cloudBlue)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(selectedLocationIds.count) of \(allLocations.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ForEach(allLocations) { location in
                                Button(action: { toggle(location.id) }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedLocationIds.contains(location.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedLocationIds.contains(location.id) ? Theme.cloudBlue : Color.gray.opacity(0.5))
                                            .font(.system(size: 20))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.name)
                                                .foregroundColor(.primary)
                                            Text(location.address)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    } header: {
                        Text("Apply To Locations")
                    } footer: {
                        if selectedLocationIds.isEmpty {
                            Text("Select at least one location.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Each location's task will be auto-assigned to a **supervisor** if one exists, otherwise to **any employee** at that location. You can change assignees afterwards.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Pre-select the location the user came from so they don't have
                // to manually re-tick it.
                if selectedLocationIds.isEmpty {
                    selectedLocationIds.insert(preselectedLocationId)
                }
                applyDefaultFrequency()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Create") {
                        Task { await save() }
                    }
                    .disabled(
                        isSaving ||
                        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        selectedLocationIds.isEmpty
                    )
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
        }
    }

    private func applyDefaultFrequency() {
        switch frequencyMode {
        case .any:
            // Honor whatever was set; default to first allowed if not in list.
            if !allowedFrequencies.contains(frequency) {
                frequency = allowedFrequencies.first ?? .oneTime
            }
        case .onlyRecurring(let defaultFreq):
            // Use supplied default the first time, otherwise keep user's pick.
            if !allowedFrequencies.contains(frequency) {
                frequency = defaultFreq
            }
        case .onlyCorrective:
            frequency = .oneTime
        }
    }

    private func toggle(_ locationId: String) {
        if selectedLocationIds.contains(locationId) {
            selectedLocationIds.remove(locationId)
        } else {
            selectedLocationIds.insert(locationId)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedLocationIds.removeAll()
        } else {
            selectedLocationIds = Set(allLocations.map { $0.id })
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = selectedLocations
        var failures: [String] = []

        // Shared id stamped on every task spawned from this single multi-location
        // create. Used later by the Edit flow to find sibling tasks at other
        // locations so changes can propagate.
        let groupId = UUID().uuidString

        for location in targets {
            // Auto-pick an assignee at this location: supervisor first, else
            // any employee, else leave unassigned.
            let autoAssigneeId = await pickAutoAssigneeId(at: location)
            let assignedIds: [String] = autoAssigneeId.map { [$0] } ?? []

            let task = WorkTask(
                id: UUID().uuidString,
                description: trimmed,
                assignedEmployeeIds: assignedIds,
                locationId: location.id,
                assignedLocationIds: [location.id],
                employeeCompletions: [:],
                frequency: frequency,
                crossLocationGroupId: groupId
            )

            do {
                // Manager-level mirror (used by manager-wide queries).
                try await FirebaseService.shared.createManagerTask(userId: userId, task: task)
                // Per-location subcollection (drives the location's task list).
                try await FirebaseService.shared.createTask(userId: userId, locationId: location.id, task: task)
                // Add the task id to the location's `tasks` array.
                var updatedLocation = location
                if !updatedLocation.tasks.contains(task.id) {
                    updatedLocation.tasks.append(task.id)
                    try await FirebaseService.shared.updateLocation(userId: userId, location: updatedLocation)
                }
            } catch {
                failures.append("\(location.name): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            onSave(targets)
            dismiss()
        } else {
            errorMessage = "Failed at:\n" + failures.joined(separator: "\n")
        }
    }

    // MARK: - Auto-assign

    // For a given location, pick a default assignee:
    //   1. The first supervisor we can find at the location, OR
    //   2. Any employee at the location, OR
    //   3. nil if the location has no people at all.
    //
    // Roles live on the `User` document, not on `Employee`, so we have to
    // fetch User records to check `.supervisor`. Done in parallel for speed;
    // `FirebaseService.fetchUser` is already cached so repeats across
    // locations are cheap.
    private func pickAutoAssigneeId(at location: Location) async -> String? {
        do {
            let employees = try await FirebaseService.shared.fetchEmployees(
                userId: userId,
                locationId: location.id
            )
            guard !employees.isEmpty else { return nil }

            let roleResults: [(id: String, role: User.UserRole?)] = await withTaskGroup(
                of: (String, User.UserRole?).self
            ) { group in
                for employee in employees {
                    group.addTask {
                        do {
                            let user = try await FirebaseService.shared.fetchUser(userId: employee.id)
                            return (employee.id, user.role)
                        } catch {
                            return (employee.id, nil)
                        }
                    }
                }

                var results: [(String, User.UserRole?)] = []
                for await tuple in group { results.append(tuple) }
                return results.map { (id: $0.0, role: $0.1) }
            }

            // Prefer any supervisor.
            if let supervisor = roleResults.first(where: { $0.role == .supervisor }) {
                return supervisor.id
            }
            // Otherwise fall back to any employee at the location.
            return roleResults.first?.id
        } catch {
            return nil
        }
    }
}
