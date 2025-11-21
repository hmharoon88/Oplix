//
//  ManagerDashboardViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class ManagerDashboardViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    var userId: String? // Set by the view that uses this ViewModel
    
    func loadLocations() async {
        guard let userId = userId else {
            errorMessage = "User ID not set"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            locations = try await firebaseService.fetchLocations(userId: userId)
        } catch {
            errorMessage = "Failed to load locations: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func deleteLocation(_ location: Location) async {
        guard let userId = userId else {
            errorMessage = "User ID not set"
            return
        }
        do {
            try await firebaseService.deleteLocation(userId: userId, locationId: location.id)
            await loadLocations()
        } catch {
            errorMessage = "Failed to delete location: \(error.localizedDescription)"
        }
    }
    
    func startObservingLocations() {
        guard let userId = userId else { return }
        let completion: ([Location]) -> Void = { [weak self] locations in
            guard let self = self else { return }
            self.locations = locations
        }
        firebaseService.observeLocations(userId: userId, completion: completion)
    }
}

