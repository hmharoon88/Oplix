//
//  ManagerOverviewViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LocationStats: Identifiable {
    let id: String
    let locationName: String
    let monthToDateSales: Double
    let monthToDateLotterySales: Double
    let monthToDatePayroll: Double
    let monthToDateExpenses: Double
    let monthToDateFuelGallons: Double
    let monthToDateFuelDollars: Double
}

@MainActor
class ManagerOverviewViewModel: ObservableObject {
    @Published var totalLocations: Int = 0
    @Published var totalEmployees: Int = 0
    @Published var totalTasks: Int = 0
    @Published var organizationName: String?
    @Published var locationStats: [LocationStats] = []
    @Published var locations: [Location] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var expiringDocuments: [Document] = []
    
    private let firebaseService = FirebaseService.shared
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func loadOverview() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let locationsTask = firebaseService.fetchLocations(userId: userId)
            async let employeesTask = firebaseService.fetchManagerEmployees(userId: userId)
            async let tasksTask = firebaseService.fetchManagerTasks(userId: userId)
            async let userTask = firebaseService.fetchUser(userId: userId)
            
            let locations = try await locationsTask
            let employees = try await employeesTask
            let tasks = try await tasksTask
            let user = try await userTask
            
            totalLocations = locations.count
            totalEmployees = employees.count
            totalTasks = tasks.count
            organizationName = user.organizationName
            self.locations = locations
            
            // Calculate location-specific stats
            await calculateLocationStats(locations: locations, employees: employees)
            
            // Check for expiring documents
            await checkExpiringDocuments()
        } catch {
            errorMessage = "Failed to load overview: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func checkExpiringDocuments() async {
        do {
            let allDocuments = try await firebaseService.fetchAllDocuments(userId: userId)
            let calendar = Calendar.current
            let oneMonthFromNow = calendar.date(byAdding: .month, value: 1, to: Date())!
            
            // Filter documents expiring within a month
            expiringDocuments = allDocuments.filter { document in
                guard let expiryDate = document.expiryDate else { return false }
                return expiryDate <= oneMonthFromNow && expiryDate >= Date()
            }
        } catch {
            // Silently fail - document expiry is not critical
            print("Failed to check expiring documents: \(error.localizedDescription)")
        }
    }
    
    private func calculateLocationStats(locations: [Location], employees: [Employee]) async {
        var stats: [LocationStats] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Get start of current month (month-to-date)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        // Month-to-date means from start of month until now
        let monthEnd = now
        
        // Create a dictionary of all employees (manager-level + location-specific) for quick lookup
        var allEmployeesDict: [String: Employee] = [:]
        for employee in employees {
            allEmployeesDict[employee.id] = employee
        }
        
        for location in locations {
            do {
                // Fetch shifts and lottery forms for this location
                let shifts = try await firebaseService.fetchShifts(userId: userId, locationId: location.id)
                let lotteryForms = try await firebaseService.fetchLotteryForms(userId: userId, locationId: location.id)
                let locationEmployees = try await firebaseService.fetchEmployees(userId: userId, locationId: location.id)
                
                // Add location employees to dictionary if not already present
                for employee in locationEmployees {
                    if allEmployeesDict[employee.id] == nil {
                        allEmployeesDict[employee.id] = employee
                    }
                }
                
                // Calculate month-to-date sales and fuel sales
                var monthToDateSales: Double = 0.0
                var monthToDateFuelGallons: Double = 0.0
                var monthToDateFuelDollars: Double = 0.0
                for shift in shifts {
                    // Determine the date to use for month-to-date filtering
                    // Priority: registerClosedAt > clockOutTime
                    // If register data exists, use registerClosedAt or clockOutTime
                    let dateToCheck: Date?
                    if shift.hasRegisterData {
                        // If register was closed, use that date; otherwise use clockOutTime
                        dateToCheck = shift.registerClosedAt ?? shift.clockOutTime
                    } else {
                        // No register data, skip this shift
                        continue
                    }
                    
                    // Check if register was closed/completed this month (month-to-date)
                    if let date = dateToCheck,
                       date >= monthStart && date <= monthEnd {
                        // Sum from all registers
                        if !shift.registers.isEmpty {
                            for register in shift.registers {
                                let cash = register.cashSale ?? 0.0
                                let credit = register.creditCard ?? 0.0
                                let fuel = register.fuelSaleDollars ?? 0.0
                                let fuelGallons = register.fuelSaleGallons ?? 0.0
                                let registerTotal = cash + credit + fuel
                                monthToDateSales += registerTotal
                                
                                // Track fuel sales separately
                                monthToDateFuelGallons += fuelGallons
                                monthToDateFuelDollars += fuel
                                
                                // Debug logging
                                if fuel > 0 {
                                    print("🔵 Fuel sales found: $\(fuel) (\(fuelGallons) gallons) for shift \(shift.id.prefix(8))")
                                }
                            }
                        } else {
                            // Legacy single register (for backward compatibility)
                            monthToDateSales += (shift.cashSale ?? 0.0) + (shift.creditCard ?? 0.0)
                        }
                    }
                }
                
                // Calculate month-to-date lottery sales
                // Uses shiftSummary.totalSoldAmount which is: instantTotal + onlineTotal
                var monthToDateLotterySales: Double = 0.0
                for form in lotteryForms {
                    // Only include forms submitted this month
                    if form.submittedAt >= monthStart && form.submittedAt <= monthEnd {
                        // Use shiftSummary.totalSoldAmount if available (new format)
                        if let shiftSummary = form.shiftSummary {
                            monthToDateLotterySales += shiftSummary.totalSoldAmount
                        } else {
                            // Fallback to old format: try to extract from formData
                            if let amountString = form.formData["amount"] ?? form.formData["sale"] ?? form.formData["total"],
                               let amount = Double(amountString) {
                                monthToDateLotterySales += amount
                            }
                        }
                    }
                }
                
                // Calculate month-to-date payroll
                var monthToDatePayroll: Double = 0.0
                var monthToDateExpenses: Double = 0.0
                let monthToDateShifts = shifts.filter { shift in
                    // Use registerClosedAt if available, otherwise clockOutTime
                    let dateToCheck = shift.registerClosedAt ?? shift.clockOutTime
                    guard let date = dateToCheck else { return false }
                    return date >= monthStart && date <= monthEnd
                }
                
                // Group shifts by employee and calculate payroll
                let shiftsByEmployee = Dictionary(grouping: monthToDateShifts, by: { $0.employeeId })
                
                for (employeeId, employeeShifts) in shiftsByEmployee {
                    guard let employee = allEmployeesDict[employeeId],
                          let hourlyRate = employee.hourlyRate else { continue }
                    
                    let totalHours = employeeShifts.compactMap { $0.hoursWorked }.reduce(0, +)
                    monthToDatePayroll += totalHours * hourlyRate
                }
                
                // Calculate month-to-date expenses from shifts
                for shift in monthToDateShifts {
                    for expense in shift.expenses {
                        monthToDateExpenses += expense.amount
                    }
                }
                
                // Debug logging for location stats
                print("🔵 Location: \(location.name)")
                print("   Month-to-date sales: $\(monthToDateSales)")
                print("   Month-to-date fuel gallons: \(monthToDateFuelGallons)")
                print("   Month-to-date fuel dollars: $\(monthToDateFuelDollars)")
                print("   Shifts with register data: \(shifts.filter { $0.hasRegisterData }.count)")
                
                stats.append(LocationStats(
                    id: location.id,
                    locationName: location.name,
                    monthToDateSales: monthToDateSales,
                    monthToDateLotterySales: monthToDateLotterySales,
                    monthToDatePayroll: monthToDatePayroll,
                    monthToDateExpenses: monthToDateExpenses,
                    monthToDateFuelGallons: monthToDateFuelGallons,
                    monthToDateFuelDollars: monthToDateFuelDollars
                ))
            } catch {
                // If fetching fails for a location, continue with others
                print("⚠️ Failed to fetch stats for location \(location.name): \(error.localizedDescription)")
            }
        }
        
        locationStats = stats
    }
}

