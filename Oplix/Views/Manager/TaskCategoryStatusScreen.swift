//
//  TaskCategoryStatusScreen.swift
//  Oplix
//
//  Created on 5/10/26.
//

import SwiftUI

// Reachable from TaskStatusView (the audit hub for one location). Shows the
// per-category audit list — TaskStatusRows with photo proof for the chosen
// category. For Corrective, also exposes an Add flow with the "Just here vs
// Multiple Locations" prompt. Tap any row to open EditTaskView.
struct TaskCategoryStatusScreen: View {
    let userId: String
    let location: Location
    let allLocations: [Location]
    let category: TaskCategory

    @ObservedObject var viewModel: LocationDetailViewModel

    /// Auth id of the person doing the audit / review. Recorded on
    /// `TaskCompletion.reviewedBy` so we know whether the manager or a
    /// supervisor approved the photo. Defaults to `userId` for the
    /// executive flow where they coincide.
    var reviewerUserId: String? = nil

    // Dismisses the entire fullScreenCover all the way back to the Task
    // Check tab. Forwarded down from TaskStatusView.
    var onDone: () -> Void = {}

    /// Effective reviewer id to attribute approvals to. Falls back to
    /// `userId` for legacy callers that didn't pass a reviewer.
    private var effectiveReviewerId: String { reviewerUserId ?? userId }

    // Pops this screen back to the Recurring/Corrective hub.
    @Environment(\.dismiss) private var dismiss

    // Tap-to-edit
    @State private var taskToEdit: WorkTask?

    // Add-task flow state — used by both the Recurring and Corrective + buttons.
    // The `category` decides which frequency mode to pass into the sheets.
    @State private var showingScopePrompt = false
    @State private var showingSingleLocationCreate = false
    @State private var showingMultiLocationCreate = false

    private var tasksInCategory: [WorkTask] {
        viewModel.tasks.filter { category.matches($0) }
    }

    // For the stats banner. "Done" = at least one assignee + every assignee
    // has completed the task in the current cycle.
    private var doneCount: Int {
        tasksInCategory.filter { task in
            !task.assignedEmployeeIds.isEmpty &&
            task.assignedEmployeeIds.allSatisfy { task.isCompletedBy(employeeId: $0) }
        }.count
    }

    private var pendingCount: Int { tasksInCategory.count - doneCount }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if !tasksInCategory.isEmpty {
                        statsBanner
                    }

                    if tasksInCategory.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(tasksInCategory) { task in
                                TaskStatusRow(
                                    task: task,
                                    employees: viewModel.employees + viewModel.supervisors,
                                    onEditTap: { taskToEdit = task },
                                    onReview: { employeeId, approved, note in
                                        Task {
                                            await viewModel.reviewCompletion(
                                                task: task,
                                                employeeId: employeeId,
                                                approved: approved,
                                                note: note,
                                                reviewerId: effectiveReviewerId
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .confirmationDialog(
            scopePromptTitle,
            isPresented: $showingScopePrompt,
            titleVisibility: .visible
        ) {
            Button("Just at \(location.name)") {
                showingSingleLocationCreate = true
            }
            Button("Pick Multiple Locations…") {
                showingMultiLocationCreate = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(scopePromptMessage)
        }
        .sheet(isPresented: $showingSingleLocationCreate) {
            AddTaskView(viewModel: viewModel, frequencyMode: addFrequencyMode)
        }
        .sheet(isPresented: $showingMultiLocationCreate) {
            AddMultiLocationTaskView(
                userId: userId,
                allLocations: allLocations,
                preselectedLocationId: location.id,
                frequencyMode: addFrequencyMode,
                onSave: { _ in
                    // The location's listener will refresh viewModel.tasks.
                }
            )
        }
        .sheet(item: $taskToEdit) { task in
            EditTaskView(viewModel: viewModel, task: task)
        }
    }

    // MARK: - Add-flow text helpers

    private var addFrequencyMode: AddTaskFrequencyMode {
        switch category {
        case .recurring: return .onlyRecurring(default: .daily)
        case .corrective: return .onlyCorrective
        }
    }

    private var scopePromptTitle: String {
        switch category {
        case .recurring: return "Add Recurring Task"
        case .corrective: return "Add Corrective Task"
        }
    }

    private var scopePromptMessage: String {
        switch category {
        case .recurring: return "Where should this recurring task apply?"
        case .corrective: return "Where should this corrective task apply?"
        }
    }

    // MARK: - Header card
    // Always-visible identity + location chip so the user knows exactly which
    // category screen they're on, regardless of how the system renders the
    // navigation title.
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(category.tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: category.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(category.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(location.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    // MARK: - Stats banner
    private var statsBanner: some View {
        HStack(spacing: 0) {
            statBox(label: "Total", value: tasksInCategory.count, color: .primary)
            Divider().frame(height: 36).background(Color.gray.opacity(0.2))
            statBox(label: "Done", value: doneCount, color: .green)
            Divider().frame(height: 36).background(Color.gray.opacity(0.2))
            statBox(label: "Pending", value: pendingCount, color: .orange)
        }
        .padding(.vertical, 12)
        .background(Theme.cloudWhite)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func statBox(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: category.iconName)
                .font(.system(size: 48))
                .foregroundColor(Theme.darkGray)
            Text(emptyStateText)
                .font(.subheadline)
                .foregroundColor(Theme.darkGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var emptyStateText: String {
        switch category {
        case .recurring: return "No recurring tasks at this location yet."
        case .corrective: return "No corrective tasks at this location yet. Tap + to add one."
        }
    }

    // MARK: - Bottom bar
    // Always shows Back (left), the category-tinted + (centre), and Done
    // (right). The + opens a "Just here vs Multiple Locations" prompt that
    // works for both Recurring and Corrective; the chosen frequency-mode
    // adapts the form (daily/weekly/monthly picker vs locked one-time).
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            backButton

            Spacer()

            Button(action: handleAddTapped) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(category.tint)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            }

            Spacer()

            doneButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var backButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                Text("Back")
                    .font(.headline)
            }
            .foregroundColor(Theme.cloudBlue)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.cloudBlue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.cloudBlue.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var doneButton: some View {
        Button(action: {
            onDone()
            dismiss()
        }) {
            Text("Done")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.3, blue: 0.6),
                            Color(red: 0.15, green: 0.4, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
    }

    private func handleAddTapped() {
        // If the manager has multiple locations, ask whether to apply this
        // task just here or across multiple. Otherwise just open the
        // single-location form directly.
        if allLocations.count > 1 {
            showingScopePrompt = true
        } else {
            showingSingleLocationCreate = true
        }
    }
}
