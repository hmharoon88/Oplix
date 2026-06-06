//
//  EditTaskView.swift
//  Oplix
//
//  Created on 5/10/26.
//

import SwiftUI

// Sheet for editing an existing task. Pre-populates description, frequency and
// assignees from the task. On save, completion data is preserved (so cycle-aware
// `isCompletedBy` keeps working naturally).
//
// If the task has a `crossLocationGroupId` (i.e. was created via the multi-
// location corrective flow) and the manager has multiple locations, save asks
// the user whether to apply changes to **just this location** or **every
// location that has this task**. Assignee changes are always local-only —
// each location has its own employees, so we never propagate assignees across
// locations.
struct EditTaskView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    let task: WorkTask

    @Environment(\.dismiss) var dismiss

    @State private var description: String
    @State private var selectedEmployeeIds: Set<String>
    @State private var frequency: TaskFrequency

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingScopePrompt = false
    @State private var showingDeleteConfirmation = false

    init(viewModel: LocationDetailViewModel, task: WorkTask) {
        self.viewModel = viewModel
        self.task = task
        _description = State(initialValue: task.description)
        _selectedEmployeeIds = State(initialValue: Set(task.assignedEmployeeIds))
        _frequency = State(initialValue: task.frequency)
    }

    private var assignableEmployees: [Employee] {
        viewModel.employees + viewModel.supervisors
    }

    private var allSelected: Bool {
        !assignableEmployees.isEmpty &&
        selectedEmployeeIds.count == assignableEmployees.count
    }

    private var hasCrossLocationSiblings: Bool {
        task.crossLocationGroupId != nil
    }

    private var frequencyFooter: String {
        switch frequency {
        case .oneTime: return "Corrective task — completes once and stays in history."
        case .daily:   return "Resets each day at midnight. Assignees see it as 'to do' again every day."
        case .weekly:  return "Resets at the start of each week."
        case .monthly: return "Resets on the 1st of each month."
        }
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

                    Section {
                        Picker("Repeat", selection: $frequency) {
                            ForEach(TaskFrequency.allCases, id: \.self) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                    } header: {
                        Text("Frequency")
                    } footer: {
                        Text(frequencyFooter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Section {
                        if assignableEmployees.isEmpty {
                            Text("No employees at this location yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: toggleSelectAll) {
                                HStack {
                                    Text(allSelected ? "Deselect All" : "Select All")
                                        .foregroundColor(Theme.cloudBlue)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(selectedEmployeeIds.count) of \(assignableEmployees.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ForEach(assignableEmployees) { employee in
                                Button(action: { toggle(employee.id) }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedEmployeeIds.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedEmployeeIds.contains(employee.id) ? Theme.cloudBlue : Color.gray.opacity(0.5))
                                            .font(.system(size: 20))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(employee.name)
                                                .foregroundColor(.primary)
                                            if viewModel.supervisors.contains(where: { $0.id == employee.id }) {
                                                Text("Supervisor")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    } header: {
                        Text("Assign To")
                    } footer: {
                        if hasCrossLocationSiblings {
                            Text("Assignee changes apply only to this location. Description and frequency changes can be applied to all locations on save.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Task")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        handleSaveTapped()
                    }
                    .disabled(
                        isSaving ||
                        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "Apply Changes",
                isPresented: $showingScopePrompt,
                titleVisibility: .visible
            ) {
                Button("Just this location") {
                    Task { await save(applyToAllLocations: false) }
                }
                Button("All locations that have this task") {
                    Task { await save(applyToAllLocations: true) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This corrective task exists at multiple locations. Where should the description and frequency changes apply?")
            }
            .alert("Delete Task", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteTask(task)
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(task.description)\"? This cannot be undone.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
        }
    }

    private func handleSaveTapped() {
        // Multi-location prompt only matters when there *could* be siblings
        // to update.
        if hasCrossLocationSiblings {
            showingScopePrompt = true
        } else {
            Task { await save(applyToAllLocations: false) }
        }
    }

    private func toggle(_ employeeId: String) {
        if selectedEmployeeIds.contains(employeeId) {
            selectedEmployeeIds.remove(employeeId)
        } else {
            selectedEmployeeIds.insert(employeeId)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedEmployeeIds.removeAll()
        } else {
            selectedEmployeeIds = Set(assignableEmployees.map { $0.id })
        }
    }

    private func save(applyToAllLocations: Bool) async {
        isSaving = true
        defer { isSaving = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableAssigneeIds = assignableEmployees
            .map { $0.id }
            .filter { selectedEmployeeIds.contains($0) }

        // 1. Always update *this* task in full (description, frequency, assignees).
        // We preserve completion data so cycle-aware logic continues to work,
        // and we preserve `createdAt` so the past-week score math doesn't
        // reset every time a task is edited.
        var updated = task
        updated = WorkTask(
            id: task.id,
            description: trimmedDescription,
            assignedEmployeeIds: stableAssigneeIds,
            locationId: task.locationId,
            assignedLocationIds: task.assignedLocationIds,
            employeeCompletions: task.employeeCompletions,
            frequency: frequency,
            crossLocationGroupId: task.crossLocationGroupId,
            createdAt: task.createdAt,
            completionHistory: task.completionHistory
        )
        await viewModel.updateTask(updated)
        if let error = viewModel.errorMessage {
            errorMessage = error
            return
        }

        // 2. If applying to all and we have a group id, fan out description +
        // frequency (NOT assignees) to siblings at other locations.
        if applyToAllLocations, let groupId = task.crossLocationGroupId {
            await propagateToSiblings(
                groupId: groupId,
                newDescription: trimmedDescription,
                newFrequency: frequency
            )
        }

        dismiss()
    }

    /// Fetches every location for the current manager, scans each location's
    /// tasks for any task with the same `crossLocationGroupId`, and updates the
    /// description and frequency on each match. Assignees are NOT propagated.
    /// Failures are swallowed but logged — partial success is acceptable for
    /// this background fan-out.
    private func propagateToSiblings(
        groupId: String,
        newDescription: String,
        newFrequency: TaskFrequency
    ) async {
        do {
            let allLocations = try await FirebaseService.shared.fetchLocations(userId: viewModel.userId)
            var failureCount = 0

            for otherLocation in allLocations where otherLocation.id != task.locationId {
                do {
                    let tasksAtLocation = try await FirebaseService.shared.fetchTasks(
                        userId: viewModel.userId,
                        locationId: otherLocation.id
                    )
                    let siblings = tasksAtLocation.filter { $0.crossLocationGroupId == groupId }
                    for sibling in siblings {
                        let updatedSibling = WorkTask(
                            id: sibling.id,
                            description: newDescription,
                            assignedEmployeeIds: sibling.assignedEmployeeIds, // unchanged
                            locationId: sibling.locationId,
                            assignedLocationIds: sibling.assignedLocationIds,
                            employeeCompletions: sibling.employeeCompletions, // unchanged
                            frequency: newFrequency,
                            crossLocationGroupId: sibling.crossLocationGroupId,
                            createdAt: sibling.createdAt, // unchanged
                            completionHistory: sibling.completionHistory
                        )
                        do {
                            try await FirebaseService.shared.updateTask(
                                userId: viewModel.userId,
                                locationId: otherLocation.id,
                                task: updatedSibling
                            )
                            // Mirror to manager-level so dashboard scores
                            // reflect description/frequency changes too.
                            do {
                                try await FirebaseService.shared.updateManagerTask(
                                    userId: viewModel.userId,
                                    task: updatedSibling
                                )
                            } catch {
                                print("EditTask: failed to mirror sibling to manager-level: \(error.localizedDescription)")
                            }
                        } catch {
                            failureCount += 1
                            print("EditTask: failed to update sibling at \(otherLocation.name): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    failureCount += 1
                    print("EditTask: failed to fetch tasks at \(otherLocation.name): \(error.localizedDescription)")
                }
            }

            if failureCount > 0 {
                errorMessage = "This location was updated, but \(failureCount) other location\(failureCount == 1 ? "" : "s") could not be updated. They may need to be edited manually."
            }
        } catch {
            errorMessage = "This location was updated, but other locations could not be reached: \(error.localizedDescription)"
        }
    }
}
