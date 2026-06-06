//
//  EmployeeManageTasksView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EmployeeManageTasksView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @State private var showingAddTask = false
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if viewModel.allTasks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "checklist")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Tasks")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("Tap the + button to add a task")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.allTasks) { task in
                        EmployeeTaskManagementRow(
                            task: task,
                            employees: viewModel.allEmployees,
                            onUpdate: { updatedTask in
                                Task {
                                    do {
                                        try await viewModel.updateTask(updatedTask)
                                    } catch {
                                        print("Failed to update task: \(error.localizedDescription)")
                                    }
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            Task {
                                do {
                                    try await viewModel.deleteTask(viewModel.allTasks[index])
                                } catch {
                                    print("Failed to delete task: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        showingAddTask = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Task")
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Manage Tasks")
        .navigationBarTitleDisplayMode(.large)
        .task {
            isLoading = true
            await viewModel.loadAllTasks()
            await viewModel.loadAllEmployees()
            isLoading = false
        }
        .sheet(isPresented: $showingAddTask) {
            EmployeeAddTaskView(viewModel: viewModel) {
                Task {
                    await viewModel.loadAllTasks()
                }
            }
        }
    }
}

struct EmployeeTaskManagementRow: View {
    let task: WorkTask
    let employees: [Employee]
    let onUpdate: (WorkTask) -> Void
    
    @State private var showingAssignment = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.description)
                .font(.headline)
                .foregroundColor(.black)
            
            if !task.assignedEmployeeIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assigned To:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(task.assignedEmployeeIds, id: \.self) { employeeId in
                        if let employee = employees.first(where: { $0.id == employeeId }) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text(employee.name)
                                    .font(.caption)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                }
            } else {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                showingAssignment = true
            }) {
                Text("Assign/Edit")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingAssignment) {
            EmployeeAssignTaskView(task: task, employees: employees, onSave: { updatedTask in
                onUpdate(updatedTask)
            })
        }
    }
}

struct EmployeeAddTaskView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var description = ""
    @State private var selectedEmployeeId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
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
                    
                    Section("Assignment") {
                        Picker("Assign To", selection: $selectedEmployeeId) {
                            Text("Unassigned").tag(String?.none)
                            ForEach(viewModel.allEmployees) { employee in
                                Text(employee.name).tag(String?.some(employee.id))
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createTask()
                        }
                    }
                    .disabled(description.isEmpty || isSaving)
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await viewModel.loadAllEmployees()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func createTask() async {
        isSaving = true
        errorMessage = nil
        
        do {
            try await viewModel.createTask(description: description, assignedEmployeeId: selectedEmployeeId)
            await MainActor.run {
                dismiss()
                onSave()
            }
        } catch {
            errorMessage = "Failed to create task: \(error.localizedDescription)"
            showingError = true
            isSaving = false
        }
    }
}

struct EmployeeAssignTaskView: View {
    let task: WorkTask
    let employees: [Employee]
    let onSave: (WorkTask) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedEmployeeIds: Set<String>
    
    init(task: WorkTask, employees: [Employee], onSave: @escaping (WorkTask) -> Void) {
        self.task = task
        self.employees = employees
        self.onSave = onSave
        _selectedEmployeeIds = State(initialValue: Set(task.assignedEmployeeIds))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Task") {
                        Text(task.description)
                            .foregroundColor(.secondary)
                    }
                    
                    Section("Assign To Employees") {
                        ForEach(employees) { employee in
                            Toggle(employee.name, isOn: Binding(
                                get: { selectedEmployeeIds.contains(employee.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedEmployeeIds.insert(employee.id)
                                    } else {
                                        selectedEmployeeIds.remove(employee.id)
                                    }
                                }
                            ))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Assign Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedTask = task
                        updatedTask.assignedEmployeeIds = Array(selectedEmployeeIds)
                        onSave(updatedTask)
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
