//
//  AddShiftView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddShiftView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedEmployeeId: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Assign Shift") {
                        Picker("Employee", selection: $selectedEmployeeId) {
                            Text("Select Employee")
                                .tag("")
                            ForEach(viewModel.employees) { employee in
                                Text(employee.name)
                                    .tag(employee.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Shift Manager")
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
                            await createShift()
                        }
                    }
                    .disabled(selectedEmployeeId.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createShift() async {
        guard !selectedEmployeeId.isEmpty else {
            errorMessage = "Please select an employee"
            showingError = true
            return
        }
        
        await viewModel.createShift(forEmployeeId: selectedEmployeeId)
        
        if viewModel.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage ?? "Failed to create shift"
            showingError = true
        }
    }
}

