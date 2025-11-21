//
//  LocationStatisticsViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class LocationStatisticsViewModel: ObservableObject {
    @Published var totalEmployees: Int = 0
    @Published var totalHours: Double = 0.0
    @Published var totalPayout: Double = 0.0
    @Published var isLoading = false
    
    private let firebaseService = FirebaseService.shared
    
    func loadStatistics(userId: String, locationId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch employees and shifts for this location
            async let employeesTask = firebaseService.fetchEmployees(userId: userId, locationId: locationId)
            async let shiftsTask = firebaseService.fetchShifts(userId: userId, locationId: locationId)
            
            let employees = try await employeesTask
            let shifts = try await shiftsTask
            
            // Calculate total employees
            totalEmployees = employees.count
            
            // Calculate total hours from completed shifts
            var totalHoursWorked: Double = 0.0
            var totalPayoutAmount: Double = 0.0
            
            // Group shifts by employee
            let shiftsByEmployee = Dictionary(grouping: shifts.filter { $0.isCompleted }, by: { $0.employeeId })
            
            for employee in employees {
                // Get all completed shifts for this employee
                let employeeShifts = shiftsByEmployee[employee.id] ?? []
                
                // Calculate total hours for this employee
                var employeeHours: Double = 0.0
                for shift in employeeShifts {
                    if let hours = shift.hoursWorked {
                        employeeHours += hours
                    }
                }
                
                totalHoursWorked += employeeHours
                
                // Calculate payout for this employee (hours × hourly rate)
                if let hourlyRate = employee.hourlyRate {
                    totalPayoutAmount += employeeHours * hourlyRate
                }
            }
            
            totalHours = totalHoursWorked
            totalPayout = totalPayoutAmount
        } catch {
            print("Error loading location statistics: \(error.localizedDescription)")
            // Set defaults on error
            totalEmployees = 0
            totalHours = 0.0
            totalPayout = 0.0
        }
    }
}

