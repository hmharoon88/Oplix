//
//  AddLocationView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddLocationView: View {
    @ObservedObject var viewModel: ManagerDashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        let _ = print("🟡 SHEET - AddLocationView BODY RENDER")
        
        return NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Location Details") {
                        TextField("Name", text: $name)
                        TextField("Address", text: $address, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("New Location")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("🟡 SHEET - AddLocationView ON APPEAR")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        print("🟡 SHEET - AddLocationView DISMISS (Cancel)")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveLocation()
                        }
                    }
                    .disabled(name.isEmpty || address.isEmpty)
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveLocation() async {
        print("🟡 SHEET - AddLocationView - Saving location")
        print("   Name: \(name)")
        print("   Address: \(address)")
        
        // Get current user ID from authenticated user
        guard let userId = authViewModel.currentUser?.id else {
            print("🟡 SHEET - AddLocationView - Error: User not logged in")
            errorMessage = "You must be logged in to create a location"
            showingError = true
            return
        }
        
        let location = Location(
            id: UUID().uuidString,
            name: name,
            address: address,
            managerId: userId, // Associate location with current user
            employees: [],
            tasks: [],
            lotteryForms: []
        )
        
        do {
            try await FirebaseService.shared.createLocation(userId: userId, location: location)
            print("🟡 SHEET - AddLocationView DISMISS (Success)")
            dismiss()
        } catch {
            print("🟡 SHEET - AddLocationView - Error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    AddLocationView(viewModel: ManagerDashboardViewModel())
}

