//
//  AddTaskView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddTaskView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var description = ""
    @State private var selectedEmployeeId: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    
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
                            ForEach(viewModel.employees) { employee in
                                Text(employee.name).tag(String?.some(employee.id))
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
        }
    }
    
    private func createTask() async {
        await viewModel.createTask(description: description, assignedToEmployeeId: selectedEmployeeId)
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

