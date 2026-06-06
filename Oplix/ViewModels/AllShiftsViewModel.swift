//
//  AllShiftsViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class AllShiftsViewModel: ObservableObject {
    @Published var shifts: [Shift] = []
    @Published var employees: [String: Employee] = [:] // employeeId -> Employee
    @Published var locations: [String: Location] = [:] // locationId -> Location
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch all locations, employees, and shifts
            async let locationsTask = firebaseService.fetchLocations(userId: userId)
            async let employeesTask = firebaseService.fetchManagerEmployees(userId: userId)
            async let shiftsTask = firebaseService.fetchAllShifts(userId: userId)
            
            let locationsList = try await locationsTask
            let employeesList = try await employeesTask
            let allShifts = try await shiftsTask
            
            // Create dictionaries for quick lookup
            var employeesDict: [String: Employee] = [:]
            var locationsDict: [String: Location] = [:]
            
            for employee in employeesList {
                employeesDict[employee.id] = employee
            }
            
            for location in locationsList {
                locationsDict[location.id] = location
                
                // Also fetch location-specific employees
                do {
                    let locationEmployees = try await firebaseService.fetchEmployees(userId: userId, locationId: location.id)
                    for employee in locationEmployees {
                        if employeesDict[employee.id] == nil {
                            employeesDict[employee.id] = employee
                        }
                    }
                } catch {
                    // Continue if fetching location employees fails
                    continue
                }
            }
            
            self.employees = employeesDict
            self.locations = locationsDict
            self.shifts = allShifts
        } catch {
            errorMessage = "Failed to load shifts: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func employeeName(for shift: Shift) -> String {
        guard let employee = employees[shift.employeeId] else {
            return "Unknown Employee"
        }
        return employee.name
    }
    
    func locationName(for shift: Shift) -> String {
        guard let location = locations[shift.locationId] else {
            return "Unknown Location"
        }
        return location.name
    }
    
    func employeeNameWithLocation(for shift: Shift) -> String {
        let name = employeeName(for: shift)
        let location = locationName(for: shift)
        return "\(name) (\(location))"
    }
}

