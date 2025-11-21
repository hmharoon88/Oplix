//
//  AddManagerTaskView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddManagerTaskView: View {
    @ObservedObject var viewModel: ManagerTasksViewModel
    @Environment(\.dismiss) var dismiss
    @State private var description = ""
    @State private var selectedLocationIds: Set<String> = []
    @State private var selectedEmployeeIds: Set<String> = []
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Task Details") {
                        TextField("Task Description", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    
                    Section("Assign to Locations (Optional)") {
                        if viewModel.locations.isEmpty {
                            Text("No locations available")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        } else {
                            ForEach(viewModel.locations) { location in
                                Toggle(location.name, isOn: Binding(
                                    get: { selectedLocationIds.contains(location.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedLocationIds.insert(location.id)
                                        } else {
                                            selectedLocationIds.remove(location.id)
                                        }
                                    }
                                ))
                            }
                        }
                    }
                    
                    Section("Assign to Employees (Optional)") {
                        if viewModel.employees.isEmpty {
                            Text("No employees available")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        } else {
                            ForEach(viewModel.employees) { employee in
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
                }
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
                    .disabled(description.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                await viewModel.loadData()
            }
        }
    }
    
    private func createTask() async {
        do {
            let assignedLocationIds = Array(selectedLocationIds)
            let assignedEmployeeIds = Array(selectedEmployeeIds)
            
            await viewModel.createTask(
                description: description,
                assignedLocationIds: assignedLocationIds,
                assignedEmployeeIds: assignedEmployeeIds
            )
            
            if viewModel.errorMessage == nil {
                dismiss()
            } else {
                errorMessage = viewModel.errorMessage ?? "Failed to create task"
                showingError = true
            }
        }
    }
}

