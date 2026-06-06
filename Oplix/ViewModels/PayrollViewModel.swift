//
//  PayrollViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct EmployeePayrollData: Identifiable {
    let id: String
    let employeeId: String
    let employeeName: String
    let locationId: String
    let locationName: String
    let hourlyRate: Double
    let totalHours: Double
    let totalPay: Double
    let shiftCount: Int
}

@MainActor
class PayrollViewModel: ObservableObject {
    @Published var payrollData: [EmployeePayrollData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: PayrollPeriod = .monthToDate
    
    enum PayrollPeriod {
        case week
        case month
        case monthToDate
        case allTime
        
        var displayName: String {
            switch self {
            case .week: return "This Week"
            case .month: return "This Month"
            case .monthToDate: return "Month to Date"
            case .allTime: return "All Time"
            }
        }
    }
    
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
                    continue
                }
            }
            
            // Filter shifts based on selected period
            let filteredShifts = filterShiftsByPeriod(allShifts, period: selectedPeriod)
            
            // Group shifts by employee and location
            let shiftsByEmployeeAndLocation = Dictionary(grouping: filteredShifts) { shift in
                "\(shift.employeeId)_\(shift.locationId)"
            }
            
            // Calculate payroll for each employee-location combination
            var payrollList: [EmployeePayrollData] = []
            
            for (key, shifts) in shiftsByEmployeeAndLocation {
                let components = key.split(separator: "_")
                guard components.count == 2,
                      let employeeId = String(components[0]) as String?,
                      let locationId = String(components[1]) as String?,
                      let employee = employeesDict[employeeId],
                      let location = locationsDict[locationId],
                      let hourlyRate = employee.hourlyRate,
                      hourlyRate > 0 else { continue }
                
                let totalHours = shifts.compactMap { $0.hoursWorked }.reduce(0, +)
                let totalPay = totalHours * hourlyRate
                
                payrollList.append(EmployeePayrollData(
                    id: key,
                    employeeId: employeeId,
                    employeeName: employee.name,
                    locationId: locationId,
                    locationName: location.name,
                    hourlyRate: hourlyRate,
                    totalHours: totalHours,
                    totalPay: totalPay,
                    shiftCount: shifts.count
                ))
            }
            
            // Sort by total pay (descending)
            self.payrollData = payrollList.sorted { $0.totalPay > $1.totalPay }
        } catch {
            errorMessage = "Failed to load payroll data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func filterShiftsByPeriod(_ shifts: [Shift], period: PayrollPeriod) -> [Shift] {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .week:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return shifts.filter { shift in
                guard let clockOutTime = shift.clockOutTime else { return false }
                return clockOutTime >= weekStart && clockOutTime <= now
            }
            
        case .month:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return shifts.filter { shift in
                guard let clockOutTime = shift.clockOutTime else { return false }
                return clockOutTime >= monthStart && clockOutTime < monthEnd
            }
            
        case .monthToDate:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return shifts.filter { shift in
                guard let clockOutTime = shift.clockOutTime else { return false }
                return clockOutTime >= monthStart && clockOutTime <= now
            }
            
        case .allTime:
            return shifts.filter { $0.clockOutTime != nil }
        }
    }
    
    var totalPayroll: Double {
        payrollData.reduce(0) { $0 + $1.totalPay }
    }
    
    var totalHours: Double {
        payrollData.reduce(0) { $0 + $1.totalHours }
    }
}

