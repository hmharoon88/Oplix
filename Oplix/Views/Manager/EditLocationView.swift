//
//  EditLocationView.swift
//  Oplix
//
//  Sheet that lets the manager rename a location and update its address
//  after creation. Mirrors AddLocationView's layout / chrome so the two
//  feel like the same screen with different verbs.
//

import SwiftUI

struct EditLocationView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var address: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(viewModel: LocationDetailViewModel) {
        self.viewModel = viewModel
        // Pre-fill from the current location so the user can tweak
        // a typo instead of retyping the whole field.
        _name = State(initialValue: viewModel.location?.name ?? "")
        _address = State(initialValue: viewModel.location?.address ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        guard let current = viewModel.location else { return false }
        return trimmedName != current.name || trimmedAddress != current.address
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !trimmedAddress.isEmpty && hasChanges && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                Form {
                    Section("Location Details") {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(false)
                        TextField("Address", text: $address, axis: .vertical)
                            .lineLimit(3...6)
                            .textInputAutocapitalization(.words)
                    }

                    Section {
                        Text("Renaming a location only changes how it appears in the app. Employees, schedules, tasks, payables, and history all stay attached to it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Couldn't save", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await viewModel.updateLocationDetails(
                name: trimmedName,
                address: trimmedAddress
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
