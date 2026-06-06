//
//  EmployeeTasksView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeTasksView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @State private var taskToComplete: WorkTask?
    @State private var showingImageCapture = false

    private var missedItems: [TaskAssignmentAudit.EmployeeMissedRecurringItem] {
        viewModel.missedRecurringItems
    }

    private var hasAnyContent: Bool {
        !viewModel.actionableTasks.isEmpty || !missedItems.isEmpty
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if !hasAnyContent {
                        emptyState
                    } else if let employee = viewModel.employee {
                        if !missedItems.isEmpty {
                            missedSection
                        }

                        if !viewModel.actionableTasks.isEmpty {
                            actionableSection(employee: employee)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .sheet(item: $taskToComplete) { task in
            TaskImageCaptureView(
                task: task,
                onImagesCaptured: { imageDataList, note in
                    viewModel.completeTaskInBackground(task, imageDataList: imageDataList, note: note)
                    showingImageCapture = false
                    taskToComplete = nil
                },
                onCancel: {
                    showingImageCapture = false
                    taskToComplete = nil
                }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundColor(Theme.darkGray)
            Text("No tasks assigned")
                .font(.subheadline)
                .foregroundColor(Theme.darkGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var missedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Missed on past days")
                    .font(.headline)
                    .foregroundColor(.black)
                Text("Recurring tasks you didn't complete. These can't be submitted now — complete today's work below.")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)

            ForEach(missedItems) { item in
                EmployeeMissedRecurringRow(item: item)
                    .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func actionableSection(employee: Employee) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !missedItems.isEmpty {
                Text("Your tasks")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal)
            }

            ForEach(viewModel.actionableTasks) { task in
                let completeAction: () -> Void = {
                    taskToComplete = task
                    showingImageCapture = true
                }
                TaskCard(
                    task: task,
                    employee: employee,
                    onComplete: completeAction
                )
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Missed (read-only)

private struct EmployeeMissedRecurringRow: View {
    let item: TaskAssignmentAudit.EmployeeMissedRecurringItem

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: item.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundColor(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.task.description)
                    .font(.body)
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)

                Text(dateLabel)
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)

                HStack(spacing: 8) {
                    Text("MISSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)

                    Text(item.task.frequency.shortName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.cloudBlue)
                        .cornerRadius(6)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.cloudWhite.opacity(0.92))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}
