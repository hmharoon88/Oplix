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
    // Merchandise sales only (cash + credit). Historically this field
    // ALSO included fuel, which double-counted it against the separate
    // monthToDateFuelDollars row in the UI. We now keep them strictly
    // disjoint so the breakdown adds up clean: merch + fuel + lottery.
    let monthToDateSales: Double
    let monthToDateLotterySales: Double
    let monthToDatePayroll: Double
    let monthToDateExpenses: Double
    let monthToDateFuelGallons: Double
    let monthToDateFuelDollars: Double
    
    // Total revenue across all streams. Computed from the disjoint
    // components above so the relationship is obvious and we can't
    // accidentally double-count again.
    var monthToDateTotalRevenue: Double {
        monthToDateSales + monthToDateFuelDollars + monthToDateLotterySales
    }
}

// Rolled-up "what's happening today" numbers shown on the Home screen.
// Aggregated across every location the manager owns. Computed during
// loadOverview so we never make a separate network round-trip just for these.
struct TodaySnapshot: Equatable {
    // Cash + credit + fuel + lottery summed across closed registers and
    // submitted lottery forms whose date stamp falls inside today.
    var revenue: Double = 0
    // Same metric for the same weekday last week — drives the trend arrow.
    // When zero we hide the trend rather than show a meaningless "▲ ∞%".
    var revenueLastWeekSameDay: Double = 0
    // Employees currently clocked in across all locations.
    var clockedInCount: Int = 0
    // How many employees have a shift assigned for today (the denominator
    // in "2 of 5" — derived from `weeklySchedule.worksOn(today)`).
    var scheduledTodayCount: Int = 0
    // Names of locations that currently have at least one employee on shift.
    // Surfaced under the count as small context.
    var clockedInLocationNames: [String] = []
    // Tasks across all locations that count as completed in the current
    // cycle (today for daily, this week for weekly, etc) divided by total
    // active tasks. Manager-level (locationless) tasks aren't counted.
    var tasksCompleted: Int = 0
    var tasksTotal: Int = 0
    
    var hasComparison: Bool { revenueLastWeekSameDay > 0 }
    
    // Signed % change vs same weekday last week. Returns nil when there's
    // no baseline (last week's number is zero) so the UI can hide the chip.
    var revenueChangePct: Double? {
        guard hasComparison else { return nil }
        return (revenue - revenueLastWeekSameDay) / revenueLastWeekSameDay * 100.0
    }
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
    @Published var todaySnapshot: TodaySnapshot = TodaySnapshot()
    
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
            
            // Calculate location-specific stats — also accumulates today's
            // snapshot data so we don't make a second pass over the shifts.
            await calculateLocationStats(locations: locations, employees: employees, tasks: tasks)
            
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
    
    private func calculateLocationStats(locations: [Location], employees: [Employee], tasks: [WorkTask]) async {
        var stats: [LocationStats] = []
        let calendar = Calendar.current
        let now = Date()
        
        // Get start of current month (month-to-date) - use start of day in local timezone
        let monthStartComponents = calendar.dateComponents([.year, .month], from: now)
        let monthStart = calendar.date(from: DateComponents(year: monthStartComponents.year, month: monthStartComponents.month, day: 1))!
        // Month-to-date means from start of month until end of today
        let monthEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        // --- Today + same-weekday-last-week ranges for the Today snapshot.
        // Using startOfDay / next-day boundaries avoids the "23:59:59 hides
        // some events" off-by-one bug seen elsewhere.
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let lastWeekSameDayStart = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let lastWeekSameDayEnd = calendar.date(byAdding: .day, value: -7, to: tomorrowStart) ?? tomorrowStart
        
        // Snapshot accumulators — filled in per-location below.
        var snapshot = TodaySnapshot()
        var clockedInLocationNames = Set<String>()
        
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
                
                // -- Today snapshot accumulation for this location ----------
                // Walk shifts once and sum cash + credit + fuel for register
                // closings dated today, plus the same date last week. Live
                // shifts (clockOutTime == nil) feed clocked-in counts.
                for shift in shifts {
                    if shift.isActive {
                        snapshot.clockedInCount += 1
                        clockedInLocationNames.insert(location.name)
                    }
                    
                    // For revenue: use registerClosedAt as the canonical
                    // "the books closed" timestamp; otherwise fall back to
                    // clockOutTime. (Matches the month-to-date logic above.)
                    let dateRef = shift.registerClosedAt ?? shift.clockOutTime
                    guard let ref = dateRef, shift.hasRegisterData else { continue }
                    let bucket: WritableKeyPath<TodaySnapshot, Double>?
                    if ref >= todayStart && ref < tomorrowStart {
                        bucket = \.revenue
                    } else if ref >= lastWeekSameDayStart && ref < lastWeekSameDayEnd {
                        bucket = \.revenueLastWeekSameDay
                    } else {
                        bucket = nil
                    }
                    guard let bucketKey = bucket else { continue }
                    
                    if !shift.registers.isEmpty {
                        for register in shift.registers {
                            let cash = register.cashSale ?? 0
                            let credit = register.creditCard ?? 0
                            let fuel = register.fuelSaleDollars ?? 0
                            snapshot[keyPath: bucketKey] += cash + credit + fuel
                        }
                    } else {
                        snapshot[keyPath: bucketKey] += (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
                    }
                }
                for form in lotteryForms {
                    let bucket: WritableKeyPath<TodaySnapshot, Double>?
                    if form.submittedAt >= todayStart && form.submittedAt < tomorrowStart {
                        bucket = \.revenue
                    } else if form.submittedAt >= lastWeekSameDayStart && form.submittedAt < lastWeekSameDayEnd {
                        bucket = \.revenueLastWeekSameDay
                    } else {
                        bucket = nil
                    }
                    guard let bucketKey = bucket else { continue }
                    snapshot[keyPath: bucketKey] += form.shiftSummary?.totalSoldAmount ?? 0
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
                        // Sum from all registers. monthToDateSales is now
                        // *merchandise only* (cash + credit). Fuel is tracked
                        // separately so the UI breakdown can show them as
                        // disjoint pieces of total revenue.
                        if !shift.registers.isEmpty {
                            for register in shift.registers {
                                let cash = register.cashSale ?? 0.0
                                let credit = register.creditCard ?? 0.0
                                let fuel = register.fuelSaleDollars ?? 0.0
                                let fuelGallons = register.fuelSaleGallons ?? 0.0
                                monthToDateSales += cash + credit
                                monthToDateFuelGallons += fuelGallons
                                monthToDateFuelDollars += fuel
                                
                                print("🔵 Shift \(shift.id.prefix(8)) on \(date): Merch=$\(cash + credit), Fuel=$\(fuel)")
                            }
                        } else {
                            // Legacy single register (for backward compatibility).
                            // No fuel on legacy single-register shifts.
                            let cash = shift.cashSale ?? 0.0
                            let credit = shift.creditCard ?? 0.0
                            monthToDateSales += cash + credit
                            print("🔵 Legacy shift \(shift.id.prefix(8)) on \(date): Merch=$\(cash + credit)")
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
        
        // -- Finalize today snapshot -------------------------------------
        // scheduledTodayCount: every employee whose weeklySchedule covers
        // today's weekday. Approximation — if an employee splits across
        // locations on different days, this still counts them once.
        var scheduledToday = 0
        for employee in employees {
            if employee.weeklySchedule?.worksOn(date: now) == true {
                scheduledToday += 1
            }
        }
        snapshot.scheduledTodayCount = scheduledToday
        // Stable display order so the UI doesn't reshuffle on each load.
        snapshot.clockedInLocationNames = Array(clockedInLocationNames).sorted()
        
        // Tasks today: across all locations, count tasks whose current
        // cycle has at least one completion that counts (= not disapproved).
        // Manager-level tasks (locationId == nil) are scheduled but
        // un-deployed; skip them to keep the denominator honest.
        var taskCompleted = 0
        var taskTotal = 0
        for task in tasks where task.locationId != nil {
            taskTotal += 1
            let hasDone = task.currentCycleCompletions.values.contains { $0.countsAsCompleted }
            if hasDone { taskCompleted += 1 }
        }
        snapshot.tasksCompleted = taskCompleted
        snapshot.tasksTotal = taskTotal
        
        locationStats = stats
        todaySnapshot = snapshot
    }
}

