//
//  LotteryFormView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryFormView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var formData: [String: String] = [:]
    @State private var notes = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Form Data") {
                        TextField("Field 1", text: Binding(
                            get: { formData["field1"] ?? "" },
                            set: { formData["field1"] = $0 }
                        ))
                        TextField("Field 2", text: Binding(
                            get: { formData["field2"] ?? "" },
                            set: { formData["field2"] = $0 }
                        ))
                        TextField("Field 3", text: Binding(
                            get: { formData["field3"] ?? "" },
                            set: { formData["field3"] = $0 }
                        ))
                    }
                    
                    Section("Notes") {
                        TextField("Additional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Lottery Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            await submitForm()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func submitForm() async {
        isSubmitting = true
        do {
            try await viewModel.submitLotteryForm(formData: formData, notes: notes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isSubmitting = false
    }
}

#Preview {
    LotteryFormView(viewModel: EmployeeHomeViewModel(employeeId: "test", locationId: "test"))
}

