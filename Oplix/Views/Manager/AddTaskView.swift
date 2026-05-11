//
//  AddTaskView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

// Constrains which frequency options the user is allowed to pick when this
// form is launched. Used so the "Recurring" + button shows only daily/weekly/
// monthly choices, and the "Corrective" + button locks the new task to one-time
// (corrective) without showing a picker at all.
enum AddTaskFrequencyMode {
    case any                                   // user picks any frequency
    case onlyRecurring(default: TaskFrequency) // only daily/weekly/monthly
    case onlyCorrective                        // locked to one-time (corrective)
}

struct AddTaskView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    var frequencyMode: AddTaskFrequencyMode = .any

    @Environment(\.dismiss) var dismiss
    @State private var description = ""
    @State private var selectedEmployeeIds: Set<String> = []
    @State private var frequency: TaskFrequency = .oneTime
    @State private var showingError = false
    @State private var errorMessage = ""

    // Combined list of who can be assigned at this location: regular employees
    // and supervisors. Both can be assigned tasks per the existing data model.
    private var assignableEmployees: [Employee] {
        viewModel.employees + viewModel.supervisors
    }

    private var allSelected: Bool {
        !assignableEmployees.isEmpty &&
        selectedEmployeeIds.count == assignableEmployees.count
    }

    private var allowedFrequencies: [TaskFrequency] {
        switch frequencyMode {
        case .any: return TaskFrequency.allCases
        case .onlyRecurring: return [.daily, .weekly, .monthly]
        case .onlyCorrective: return [.oneTime]
        }
    }

    private var navigationTitleText: String {
        switch frequencyMode {
        case .any: return "New Task"
        case .onlyRecurring: return "New Recurring Task"
        case .onlyCorrective: return "New Corrective Task"
        }
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

                    // Frequency picker — only shown when the user is allowed to choose.
                    // For .onlyCorrective we hide it (the title already says "Corrective").
                    if case .onlyCorrective = frequencyMode {
                        // No picker — just show the locked-type explanation.
                        Section {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundColor(Theme.cloudBlue)
                                Text("Corrective Task")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("One-time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } footer: {
                            Text(frequencyFooter)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Section {
                            Picker("Repeat", selection: $frequency) {
                                ForEach(allowedFrequencies, id: \.self) { freq in
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
                    }

                    Section {
                        if assignableEmployees.isEmpty {
                            Text("No employees at this location yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            // Quick toggle: select / deselect everyone at this location.
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
                        if selectedEmployeeIds.isEmpty && !assignableEmployees.isEmpty {
                            Text("Tasks with no assignees won't appear in any employee's task list.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Apply the initial frequency based on the launch mode.
                applyDefaultFrequency()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createTask() }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func applyDefaultFrequency() {
        switch frequencyMode {
        case .any:
            // Keep whatever it was, default initial is .oneTime.
            break
        case .onlyRecurring(let defaultFreq):
            // If the picker only allows recurring options but state is still
            // .oneTime from initialization, snap to the default.
            if !allowedFrequencies.contains(frequency) {
                frequency = defaultFreq
            }
        case .onlyCorrective:
            frequency = .oneTime
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

    private func createTask() async {
        // Stable order so the saved array reflects the on-screen order.
        let assignedIds = assignableEmployees
            .map { $0.id }
            .filter { selectedEmployeeIds.contains($0) }

        await viewModel.createTask(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            assignedEmployeeIds: assignedIds,
            frequency: frequency
        )
        if let error = viewModel.errorMessage {
            errorMessage = error
            showingError = true
        } else {
            dismiss()
        }
    }
}

#Preview {
    AddTaskView(viewModel: LocationDetailViewModel(userId: "test-user", locationId: "test-location"))
}
