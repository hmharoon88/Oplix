//
//  EmployeeRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EmployeeRow: View {
    let employee: Employee
    // Optional task list used to render today's task-completion progress.
    // When nil the row falls back to its old appearance (just shift status).
    var tasks: [WorkTask]? = nil

    private var progress: (completed: Int, assigned: Int)? {
        guard let tasks = tasks else { return nil }
        let result = TaskProgress.employeeToday(tasks: tasks, employeeId: employee.id)
        // Don't show a 0/0 chip — looks like a bug rather than "no work".
        guard result.assigned > 0 else { return nil }
        return result
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(employee.name)
                    .font(.headline)
                Text(employee.username)
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
            }
            Spacer()

            if let progress = progress {
                taskProgressBadge(completed: progress.completed, total: progress.assigned)
            }

            Text(employee.currentShiftStatus.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(employee.currentShiftStatus == .clockedIn ? Color.green.opacity(0.2) : Theme.darkGray.opacity(0.2))
                .cornerRadius(8)
        }
        .padding()
        .cloudCard()
    }

    @ViewBuilder
    private func taskProgressBadge(completed: Int, total: Int) -> some View {
        let isDone = completed == total
        let isPartial = completed > 0 && completed < total
        let color: Color = isDone ? .green : (isPartial ? .orange : .gray)

        HStack(spacing: 4) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 11, weight: .semibold))
            Text("\(completed)/\(total)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
}
