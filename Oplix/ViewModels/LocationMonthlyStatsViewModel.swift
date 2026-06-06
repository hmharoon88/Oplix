//
//  LocationMonthlyStatsViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct DailyStats: Identifiable {
    let id: String // Format: "YYYY-MM-DD"
    let date: Date
    let dayName: String
    let sales: Double // Cash + Credit Card
    let expenses: Double // Cash + Non-cash expenses
    let fuelGallons: Double
    let fuelDollars: Double
}

struct MonthlyStats: Identifiable {
    let id: String // Format: "YYYY-MM"
    let year: Int
    let month: Int
    let monthName: String
    let sales: Double
    let lotterySales: Double
    let payroll: Double
    let expenses: Double
    let dailyStats: [DailyStats] // Daily breakdown for this month
}

struct YearlyStats: Identifiable {
    let id: Int // Year
    let year: Int
    var monthlyStats: [MonthlyStats]
    var totalSales: Double {
        monthlyStats.reduce(0) { $0 + $1.sales }
    }
    var totalLotterySales: Double {
        monthlyStats.reduce(0) { $0 + $1.lotterySales }
    }
    var totalPayroll: Double {
        monthlyStats.reduce(0) { $0 + $1.payroll }
    }
    var totalExpenses: Double {
        monthlyStats.reduce(0) { $0 + $1.expenses }
    }
}

@MainActor
class LocationMonthlyStatsViewModel: ObservableObject {
    @Published var locationName: String
    @Published var yearlyStats: [YearlyStats] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var expandedYears: Set<Int> = []
    @Published var expandedMonths: Set<String> = [] // Track which months are expanded to show daily table
    
    private let firebaseService = FirebaseService.shared
    private let userId: String
    private let locationId: String
    
    init(userId: String, locationId: String, locationName: String) {
        self.userId = userId
        self.locationId = locationId
        self.locationName = locationName
    }
    
    func loadMonthlyStats() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch all shifts and lottery forms for this location
            let shifts = try await firebaseService.fetchShifts(userId: userId, locationId: locationId)
            let lotteryForms = try await firebaseService.fetchLotteryForms(userId: userId, locationId: locationId)
            let employees = try await firebaseService.fetchEmployees(userId: userId, locationId: locationId)
            
            // Create employee lookup dictionary
            var employeeDict: [String: Employee] = [:]
            for employee in employees {
                employeeDict[employee.id] = employee
            }
            
            // Group shifts by date (daily) and by month
            var dailyData: [String: (sales: Double, expenses: Double, fuelGallons: Double, fuelDollars: Double, lotterySales: Double, payroll: Double)] = [:]
            var monthlyData: [String: (sales: Double, lotterySales: Double, payroll: Double, expenses: Double)] = [:]
            
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            let dayNameFormatter = DateFormatter()
            dayNameFormatter.dateFormat = "EEEE" // Day name (Monday, Tuesday, etc.)
            
            // Process shifts - group by date for daily stats
            print("🔵 LocationMonthlyStatsViewModel: Processing \(shifts.count) shifts")
            for shift in shifts {
                // Determine the date to use (priority: registerClosedAt > clockOutTime > clockInTime)
                let dateToUse: Date?
                if shift.hasRegisterData {
                    dateToUse = shift.registerClosedAt ?? shift.clockOutTime ?? shift.clockInTime
                } else {
                    dateToUse = shift.clockOutTime ?? shift.clockInTime
                }
                
                guard let date = dateToUse else {
                    print("⚠️ LocationMonthlyStatsViewModel: Shift \(shift.id.prefix(8)) skipped - no date available")
                    print("   registerClosedAt: \(shift.registerClosedAt?.description ?? "nil")")
                    print("   clockOutTime: \(shift.clockOutTime?.description ?? "nil")")
                    print("   clockInTime: \(shift.clockInTime?.description ?? "nil")")
                    print("   hasRegisterData: \(shift.hasRegisterData)")
                    continue
                }
                
                let dayKey = dayFormatter.string(from: date)
                let monthKey = dateFormatter.string(from: date)
                
                // Debug logging for December shifts
                let dateYear = calendar.component(.year, from: date)
                let dateMonth = calendar.component(.month, from: date)
                if dateYear == 2025 && dateMonth == 12 {
                    print("🔵 Processing December shift \(shift.id.prefix(8)) on \(dayKey)")
                }
                
                // Initialize daily data if needed
                if dailyData[dayKey] == nil {
                    dailyData[dayKey] = (sales: 0, expenses: 0, fuelGallons: 0, fuelDollars: 0, lotterySales: 0, payroll: 0)
                }
                
                // Initialize monthly data if needed
                if monthlyData[monthKey] == nil {
                    monthlyData[monthKey] = (sales: 0, lotterySales: 0, payroll: 0, expenses: 0)
                }
                
                // Calculate sales from registers (including fuel)
                var shiftSales: Double = 0.0
                var shiftFuelGallons: Double = 0.0
                var shiftFuelDollars: Double = 0.0
                
                if !shift.registers.isEmpty {
                    for register in shift.registers {
                        shiftSales += (register.cashSale ?? 0.0) + (register.creditCard ?? 0.0)
                        shiftFuelGallons += register.fuelSaleGallons ?? 0.0
                        shiftFuelDollars += register.fuelSaleDollars ?? 0.0
                    }
                } else {
                    // Legacy single register
                    shiftSales += (shift.cashSale ?? 0.0) + (shift.creditCard ?? 0.0)
                }
                
                dailyData[dayKey]?.sales += shiftSales
                dailyData[dayKey]?.fuelGallons += shiftFuelGallons
                dailyData[dayKey]?.fuelDollars += shiftFuelDollars
                monthlyData[monthKey]?.sales += shiftSales
                
                // Calculate expenses (cash + non-cash)
                var shiftExpenses: Double = 0.0
                
                // Add non-cash expenses
                for expense in shift.expenses {
                    shiftExpenses += expense.amount
                }
                
                // Add cash expenses from registers
                if !shift.registers.isEmpty {
                    for register in shift.registers {
                        // Sum all cash expense amounts
                        if let amounts = register.cashExpenseAmounts {
                            shiftExpenses += amounts.reduce(0, +)
                        } else if let amount = register.cashExpense {
                            shiftExpenses += amount
                        }
                    }
                }
                
                dailyData[dayKey]?.expenses += shiftExpenses
                monthlyData[monthKey]?.expenses += shiftExpenses
                
                // Add payroll
                if let hoursWorked = shift.hoursWorked,
                   let employee = employeeDict[shift.employeeId],
                   let hourlyRate = employee.hourlyRate {
                    let payrollAmount = hoursWorked * hourlyRate
                    dailyData[dayKey]?.payroll += payrollAmount
                    monthlyData[monthKey]?.payroll += payrollAmount
                }
            }
            
            // Process lottery forms
            for form in lotteryForms {
                let dayKey = dayFormatter.string(from: form.submittedAt)
                let monthKey = dateFormatter.string(from: form.submittedAt)
                
                // Initialize if needed
                if dailyData[dayKey] == nil {
                    dailyData[dayKey] = (sales: 0, expenses: 0, fuelGallons: 0, fuelDollars: 0, lotterySales: 0, payroll: 0)
                }
                if monthlyData[monthKey] == nil {
                    monthlyData[monthKey] = (sales: 0, lotterySales: 0, payroll: 0, expenses: 0)
                }
                
                // Extract sale amount
                var lotteryAmount: Double = 0.0
                if let shiftSummary = form.shiftSummary {
                    lotteryAmount = shiftSummary.totalSoldAmount
                } else if let amountString = form.formData["amount"] ?? form.formData["sale"] ?? form.formData["total"],
                          let amount = Double(amountString) {
                    lotteryAmount = amount
                }
                
                dailyData[dayKey]?.lotterySales += lotteryAmount
                monthlyData[monthKey]?.lotterySales += lotteryAmount
            }
            
            // Convert daily data to DailyStats and group by month
            var dailyStatsByMonth: [String: [DailyStats]] = [:]
            let dayNameFormatter2 = DateFormatter()
            dayNameFormatter2.dateFormat = "EEEE"
            
            for (dayKey, data) in dailyData {
                guard let date = dayFormatter.date(from: dayKey) else { continue }
                let monthKey = dateFormatter.string(from: date)
                let dayName = dayNameFormatter2.string(from: date)
                
                let dailyStat = DailyStats(
                    id: dayKey,
                    date: date,
                    dayName: dayName,
                    sales: data.sales,
                    expenses: data.expenses,
                    fuelGallons: data.fuelGallons,
                    fuelDollars: data.fuelDollars
                )
                
                if dailyStatsByMonth[monthKey] == nil {
                    dailyStatsByMonth[monthKey] = []
                }
                dailyStatsByMonth[monthKey]?.append(dailyStat)
            }
            
            // Sort daily stats by date within each month
            for monthKey in dailyStatsByMonth.keys {
                dailyStatsByMonth[monthKey]?.sort { $0.date < $1.date }
            }
            
            // Convert to MonthlyStats and group by year
            var monthlyStats: [MonthlyStats] = []
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            
            for (monthKey, data) in monthlyData {
                let components = monthKey.split(separator: "-")
                guard components.count == 2,
                      let year = Int(components[0]),
                      let month = Int(components[1]) else { continue }
                
                let date = calendar.date(from: DateComponents(year: year, month: month))!
                let monthName = monthFormatter.string(from: date)
                
                // Get daily stats for this month
                let dailyStats = dailyStatsByMonth[monthKey] ?? []
                
                monthlyStats.append(MonthlyStats(
                    id: monthKey,
                    year: year,
                    month: month,
                    monthName: monthName,
                    sales: data.sales,
                    lotterySales: data.lotterySales,
                    payroll: data.payroll,
                    expenses: data.expenses,
                    dailyStats: dailyStats
                ))
            }
            
            // Sort by year and month (newest first)
            monthlyStats.sort { stats1, stats2 in
                if stats1.year != stats2.year {
                    return stats1.year > stats2.year
                }
                return stats1.month > stats2.month
            }
            
            // Group by year
            let groupedByYear = Dictionary(grouping: monthlyStats, by: { $0.year })
            yearlyStats = groupedByYear.map { year, stats in
                YearlyStats(id: year, year: year, monthlyStats: stats)
            }.sorted { $0.year > $1.year } // Newest year first
            
            // Expand current year by default
            let currentYear = calendar.component(.year, from: Date())
            expandedYears.insert(currentYear)
            
        } catch {
            errorMessage = "Failed to load monthly stats: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func toggleYear(_ year: Int) {
        if expandedYears.contains(year) {
            expandedYears.remove(year)
        } else {
            expandedYears.insert(year)
        }
    }
    
    func toggleMonth(_ monthId: String) {
        if expandedMonths.contains(monthId) {
            expandedMonths.remove(monthId)
        } else {
            expandedMonths.insert(monthId)
        }
    }
}

