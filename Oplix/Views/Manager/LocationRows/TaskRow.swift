//
//  TaskRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct TaskRow: View {
    let task: WorkTask
    @ObservedObject var viewModel: LocationDetailViewModel
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    // Completion is tracked per-employee via `employeeCompletions`. The
    // legacy `isCompleted` setter is a no-op, so this row is read-only;
    // employees mark their own completion (with photo proof) in
    // EmployeeTasksView, and the manager just observes the result here.
    private var assignedCount: Int {
        task.assignedEmployeeIds.count
    }

    private var completedCount: Int {
        // Only count completions for employees who are *currently* assigned and
        // whose completion is in the *current* cycle. `isCompletedBy` already
        // applies the cycle-aware check for daily/weekly/monthly tasks, so
        // recurring rows visually reset at each cycle boundary.
        task.assignedEmployeeIds.filter { task.isCompletedBy(employeeId: $0) }.count
    }

    private var isFullyComplete: Bool {
        assignedCount > 0 && completedCount == assignedCount
    }

    private var isPartiallyComplete: Bool {
        completedCount > 0 && completedCount < assignedCount
    }

    private var assigneeNames: [String] {
        task.assignedEmployeeIds.compactMap { id in
            viewModel.employees.first(where: { $0.id == id })?.name
                ?? viewModel.supervisors.first(where: { $0.id == id })?.name
        }
    }

    private var assigneeText: String {
        if task.assignedEmployeeIds.isEmpty { return "Unassigned" }
        let names = assigneeNames
        if names.isEmpty { return "\(task.assignedEmployeeIds.count) assigned" }
        return names.joined(separator: ", ")
    }

    private var statusIconName: String {
        if isFullyComplete { return "checkmark.circle.fill" }
        if isPartiallyComplete { return "circle.lefthalf.filled" }
        return "circle"
    }

    private var statusIconColor: Color {
        if isFullyComplete { return .green }
        if isPartiallyComplete { return .orange }
        return .gray
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Theme.cloudBlue : Color.gray.opacity(0.5))
                    .transition(.opacity.combined(with: .scale))
            } else {
                Image(systemName: statusIconName)
                    .font(.system(size: 22))
                    .foregroundColor(statusIconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(task.description)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .strikethrough(isFullyComplete)

                    if task.frequency.isRecurring {
                        Text(task.frequency.shortName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.cloudBlue)
                            .cornerRadius(8)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: task.assignedEmployeeIds.isEmpty ? "person.slash" : "person.2.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(assigneeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if assignedCount > 0 {
                Text("\(completedCount)/\(assignedCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isFullyComplete ? .green : (isPartiallyComplete ? .orange : .gray))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                isFullyComplete ? Color.green.opacity(0.15) :
                                (isPartiallyComplete ? Color.orange.opacity(0.15) : Color.gray.opacity(0.12))
                            )
                    )
            }
        }
        .padding(14)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelectionMode && isSelected ? Theme.cloudBlue : statusIconColor.opacity(0.2),
                    lineWidth: isSelectionMode && isSelected ? 2 : 1
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    }
}
