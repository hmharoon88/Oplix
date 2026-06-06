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
        
        // Get start of current month (month-to-date) - use start of day in local timezone
        let monthStartComponents = calendar.dateComponents([.year, .month], from: now)
        let monthStart = calendar.date(from: DateComponents(year: monthStartComponents.year, month: monthStartComponents.month, day: 1))!
        // Month-to-date means from start of month until end of today
        let monthEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        print("🔵 Month-to-date calculation:")
        print("   Month start: \(monthStart)")
        print("   Month end: \(monthEnd)")
        print("   Current date: \(now)")
        
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
                
                print("🔵 Calculating month-to-date for location: \(location.name)")
                print("   Month start: \(monthStart)")
                print("   Month end: \(monthEnd)")
                print("   Total shifts fetched: \(shifts.count)")
                
                // Log all shifts first
                for shift in shifts {
                    let dateStr = (shift.registerClosedAt ?? shift.clockOutTime ?? shift.clockInTime)?.description ?? "no date"
                    let hasData = shift.hasRegisterData ? "YES" : "NO"
                    print("   Shift \(shift.id.prefix(8)): date=\(dateStr), hasRegisterData=\(hasData), registers.count=\(shift.registers.count)")
                }
                
                var shiftsWithRegisterData = 0
                var shiftsInMonth = 0
                var shiftsSkippedNoDate = 0
                var shiftsSkippedNoRegisterData = 0
                
                for shift in shifts {
                    // Check if shift has register data
                    if !shift.hasRegisterData {
                        shiftsSkippedNoRegisterData += 1
                        continue
                    }
                    
                    shiftsWithRegisterData += 1
                    
                    // Determine the date to use for month-to-date filtering
                    // Priority: registerClosedAt > clockOutTime > clockInTime (fallback)
                    var dateToCheck: Date?
                    if let registerClosed = shift.registerClosedAt {
                        dateToCheck = registerClosed
                    } else if let clockOut = shift.clockOutTime {
                        dateToCheck = clockOut
                    } else if let clockIn = shift.clockInTime {
                        // Fallback to clock in time if no other date available
                        dateToCheck = clockIn
                    }
                    
                    guard let date = dateToCheck else {
                        print("⚠️ Shift \(shift.id.prefix(8)) has register data but no date available")
                        print("   registerClosedAt: \(shift.registerClosedAt?.description ?? "nil")")
                        print("   clockOutTime: \(shift.clockOutTime?.description ?? "nil")")
                        print("   clockInTime: \(shift.clockInTime?.description ?? "nil")")
                        continue
                    }
                    
                    // Check if register was closed/completed this month (month-to-date)
                    // Compare dates by calendar components to avoid timezone issues
                    let dateYear = calendar.component(.year, from: date)
                    let dateMonth = calendar.component(.month, from: date)
                    let dateDay = calendar.component(.day, from: date)
                    
                    let startYear = calendar.component(.year, from: monthStart)
                    let startMonth = calendar.component(.month, from: monthStart)
                    let startDay = calendar.component(.day, from: monthStart)
                    
                    let endYear = calendar.component(.year, from: monthEnd)
                    let endMonth = calendar.component(.month, from: monthEnd)
                    let endDay = calendar.component(.day, from: monthEnd)
                    
                    // Check if date is within the month range
                    let isInMonth = (dateYear > startYear || (dateYear == startYear && dateMonth > startMonth) || 
                                    (dateYear == startYear && dateMonth == startMonth && dateDay >= startDay)) &&
                                   (dateYear < endYear || (dateYear == endYear && dateMonth < endMonth) ||
                                    (dateYear == endYear && dateMonth == endMonth && dateDay <= endDay))
                    
                    if isInMonth {
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
                                
                                print("🔵 Shift \(shift.id.prefix(8)) on \(date): Cash=$\(cash), Credit=$\(credit), Fuel=$\(fuel), Total=$\(registerTotal)")
                                
                                // Debug logging
                                if fuel > 0 {
                                    print("🔵 Fuel sales found: $\(fuel) (\(fuelGallons) gallons) for shift \(shift.id.prefix(8))")
                                }
                            }
                        } else {
                            // Legacy single register (for backward compatibility)
                            let cash = shift.cashSale ?? 0.0
                            let credit = shift.creditCard ?? 0.0
                            let total = cash + credit
                            monthToDateSales += total
                            print("🔵 Legacy shift \(shift.id.prefix(8)) on \(date): Cash=$\(cash), Credit=$\(credit), Total=$\(total)")
                        }
                    } else {
                        print("⚠️ Shift \(shift.id.prefix(8)) date \(date) is outside month range (before \(monthStart) or after \(monthEnd))")
                    }
                }
                
                print("🔵 Summary for \(location.name):")
                print("   Shifts with register data: \(shiftsWithRegisterData)")
                print("   Shifts in current month: \(shiftsInMonth)")
                print("   Shifts skipped (no date): \(shiftsSkippedNoDate)")
                print("   Shifts skipped (no register data): \(shiftsSkippedNoRegisterData)")
                print("   Final totals - Sales=$\(monthToDateSales), Fuel=$\(monthToDateFuelDollars), Gallons=\(monthToDateFuelGallons)")
                
                // Calculate month-to-date lottery sales
                // Uses shiftSummary.totalSoldAmount which is: instantTotal + onlineTotal
                var monthToDateLotterySales: Double = 0.0
                for form in lotteryForms {
                    // Only include forms submitted this month (use calendar components for comparison)
                    let formYear = calendar.component(.year, from: form.submittedAt)
                    let formMonth = calendar.component(.month, from: form.submittedAt)
                    let formDay = calendar.component(.day, from: form.submittedAt)
                    
                    let startYear = calendar.component(.year, from: monthStart)
                    let startMonth = calendar.component(.month, from: monthStart)
                    let startDay = calendar.component(.day, from: monthStart)
                    
                    let endYear = calendar.component(.year, from: monthEnd)
                    let endMonth = calendar.component(.month, from: monthEnd)
                    let endDay = calendar.component(.day, from: monthEnd)
                    
                    let isInMonth = (formYear > startYear || (formYear == startYear && formMonth > startMonth) || 
                                    (formYear == startYear && formMonth == startMonth && formDay >= startDay)) &&
                                   (formYear < endYear || (formYear == endYear && formMonth < endMonth) ||
                                    (formYear == endYear && formMonth == endMonth && formDay <= endDay))
                    
                    if isInMonth {
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
                
                // Calculate month-to-date payroll and expenses
                var monthToDatePayroll: Double = 0.0
                var monthToDateExpenses: Double = 0.0
                let monthToDateShifts = shifts.filter { shift in
                    // Use registerClosedAt if available, otherwise clockOutTime, fallback to clockInTime
                    let dateToCheck = shift.registerClosedAt ?? shift.clockOutTime ?? shift.clockInTime
                    guard let date = dateToCheck else { return false }
                    
                    // Use calendar components for comparison to avoid timezone issues
                    let dateYear = calendar.component(.year, from: date)
                    let dateMonth = calendar.component(.month, from: date)
                    let dateDay = calendar.component(.day, from: date)
                    
                    let startYear = calendar.component(.year, from: monthStart)
                    let startMonth = calendar.component(.month, from: monthStart)
                    let startDay = calendar.component(.day, from: monthStart)
                    
                    let endYear = calendar.component(.year, from: monthEnd)
                    let endMonth = calendar.component(.month, from: monthEnd)
                    let endDay = calendar.component(.day, from: monthEnd)
                    
                    let isInMonth = (dateYear > startYear || (dateYear == startYear && dateMonth > startMonth) || 
                                    (dateYear == startYear && dateMonth == startMonth && dateDay >= startDay)) &&
                                   (dateYear < endYear || (dateYear == endYear && dateMonth < endMonth) ||
                                    (dateYear == endYear && dateMonth == endMonth && dateDay <= endDay))
                    
                    return isInMonth
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
                    // Add non-cash expenses
                    for expense in shift.expenses {
                        monthToDateExpenses += expense.amount
                    }
                    
                    // Add cash expenses from registers
                    if !shift.registers.isEmpty {
                        for register in shift.registers {
                            if let amounts = register.cashExpenseAmounts {
                                monthToDateExpenses += amounts.reduce(0, +)
                            } else if let amount = register.cashExpense {
                                // Legacy single cash expense
                                monthToDateExpenses += amount
                            }
                        }
                    }
                }
                
                print("🔵 Expenses calculation for \(location.name):")
                print("   Month-to-date shifts for expenses: \(monthToDateShifts.count)")
                print("   Month-to-date expenses: $\(monthToDateExpenses)")
                
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

