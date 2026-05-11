//
//  TaskCategoryListScreen.swift
//  Oplix
//
//  Created on 5/10/26.
//

import SwiftUI

// Reachable from TasksScreen (the "hub" with two category cards). Shows the
// list of tasks for a single category (Recurring or Corrective) and handles
// all of the management actions for that category: add, swipe-delete, multi-
// select bulk delete, and tap-to-edit.
//
// The two category screens are intentionally identical except for which tasks
// they show and what kind of task the + button creates — kept as one
// parameterized screen rather than two separate views to avoid drift.

enum TaskCategory: Hashable {
    case recurring
    case corrective

    var title: String {
        switch self {
        case .recurring: return "Recurring"
        case .corrective: return "Corrective"
        }
    }

    var iconName: String {
        switch self {
        case .recurring: return "arrow.triangle.2.circlepath"
        case .corrective: return "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recurring: return Theme.cloudBlue
        case .corrective: return .orange
        }
    }

    var subtitle: String {
        switch self {
        case .recurring: return "Daily, weekly, or monthly tasks that auto-reset each cycle."
        case .corrective: return "Ad-hoc one-time tasks for fixes and audit findings."
        }
    }

    var addFrequencyMode: AddTaskFrequencyMode {
        switch self {
        case .recurring: return .onlyRecurring(default: .daily)
        case .corrective: return .onlyCorrective
        }
    }

    var emptyStateText: String {
        switch self {
        case .recurring: return "No recurring tasks yet. Tap + to create the first one."
        case .corrective: return "No corrective tasks yet. Tap + to create the first one."
        }
    }

    func matches(_ task: WorkTask) -> Bool {
        switch self {
        case .recurring: return task.frequency.isRecurring
        case .corrective: return task.frequency == .oneTime
        }
    }
}

struct TaskCategoryListScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    let category: TaskCategory

    // Single delete
    @State private var taskToDelete: WorkTask?
    @State private var showingDeleteConfirmation = false

    // Multi-select / bulk delete
    @State private var isSelectionMode = false
    @State private var selectedTaskIds: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false

    // Add-task sheet
    @State private var showingAddTask = false

    // Tap-to-edit
    @State private var taskToEdit: WorkTask?

    private var tasksInCategory: [WorkTask] {
        viewModel.tasks.filter { category.matches($0) }
    }

    // For the stats banner. Same definition of "done" as the audit screen so
    // the two views agree on terminology.
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

            VStack(spacing: 12) {
                headerCard
                if !tasksInCategory.isEmpty {
                    statsBanner
                }

                if tasksInCategory.isEmpty {
                    emptyState
                    Spacer()
                } else {
                    taskList
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView(viewModel: viewModel, frequencyMode: category.addFrequencyMode)
        }
        .sheet(item: $taskToEdit) { task in
            EditTaskView(viewModel: viewModel, task: task)
        }
        .alert(
            "Delete Task",
            isPresented: $showingDeleteConfirmation,
            presenting: taskToDelete
        ) { task in
            Button("Cancel", role: .cancel) { taskToDelete = nil }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteTask(task)
                    taskToDelete = nil
                }
            }
        } message: { task in
            Text("Are you sure you want to delete \"\(task.description)\"? This cannot be undone.")
        }
        .alert(
            "Delete \(selectedTaskIds.count) Task\(selectedTaskIds.count == 1 ? "" : "s")",
            isPresented: $showingBulkDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performBulkDelete() }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedTaskIds.count) task\(selectedTaskIds.count == 1 ? "" : "s")? This cannot be undone.")
        }
    }

    // MARK: - List
    private var taskList: some View {
        List {
            ForEach(tasksInCategory) { task in
                taskListItem(task: task)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func taskListItem(task: WorkTask) -> some View {
        let isSelected = selectedTaskIds.contains(task.id)
        if isSelectionMode {
            TaskRow(
                task: task,
                viewModel: viewModel,
                isSelectionMode: true,
                isSelected: isSelected
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(task) }
        } else {
            TaskRow(task: task, viewModel: viewModel)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .contentShape(Rectangle())
                .onTapGesture { taskToEdit = task }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        taskToDelete = task
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    // MARK: - Header card
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
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
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
            Text(category.emptyStateText)
                .font(.subheadline)
                .foregroundColor(Theme.darkGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Bottom action bar
    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            if isSelectionMode {
                Button(action: exitSelectionMode) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }

                Spacer()

                Text("\(selectedTaskIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                Button(action: handleBulkDeleteTapped) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(selectedTaskIds.isEmpty ? Color.gray.opacity(0.5) : Color.green)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(selectedTaskIds.isEmpty)
            } else {
                Button(action: enterSelectionMode) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(tasksInCategory.isEmpty)
                .opacity(tasksInCategory.isEmpty ? 0.4 : 1)

                Spacer()

                Button(action: { showingAddTask = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(category.tint)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Selection helpers
    private func enterSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = true
            selectedTaskIds = []
        }
    }

    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = false
            selectedTaskIds = []
        }
    }

    private func toggleSelection(_ task: WorkTask) {
        if selectedTaskIds.contains(task.id) {
            selectedTaskIds.remove(task.id)
        } else {
            selectedTaskIds.insert(task.id)
        }
    }

    private func handleBulkDeleteTapped() {
        guard !selectedTaskIds.isEmpty else { return }
        showingBulkDeleteConfirmation = true
    }

    private func performBulkDelete() async {
        let tasksToDelete = tasksInCategory.filter { selectedTaskIds.contains($0.id) }
        for task in tasksToDelete {
            await viewModel.deleteTask(task)
        }
        exitSelectionMode()
    }
}
