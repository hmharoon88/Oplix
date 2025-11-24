//
//  LocationMonthlyStatsViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct MonthlyStats: Identifiable {
    let id: String // Format: "YYYY-MM"
    let year: Int
    let month: Int
    let monthName: String
    let sales: Double
    let lotterySales: Double
    let payroll: Double
    let expenses: Double
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
            
            // Group shifts and forms by month
            var monthlyData: [String: (sales: Double, lotterySales: Double, payroll: Double, expenses: Double)] = [:]
            
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM"
            
            // Process shifts
            for shift in shifts {
                guard let clockOutTime = shift.clockOutTime else { continue }
                
                let monthKey = dateFormatter.string(from: clockOutTime)
                
                // Initialize if needed
                if monthlyData[monthKey] == nil {
                    monthlyData[monthKey] = (sales: 0, lotterySales: 0, payroll: 0, expenses: 0)
                }
                
                // Add sales
                monthlyData[monthKey]?.sales += (shift.cashSale ?? 0.0) + (shift.creditCard ?? 0.0)
                
                // Add expenses
                for expense in shift.expenses {
                    monthlyData[monthKey]?.expenses += expense.amount
                }
                
                // Add payroll
                if let hoursWorked = shift.hoursWorked,
                   let employee = employeeDict[shift.employeeId],
                   let hourlyRate = employee.hourlyRate {
                    monthlyData[monthKey]?.payroll += hoursWorked * hourlyRate
                }
            }
            
            // Process lottery forms
            for form in lotteryForms {
                let monthKey = dateFormatter.string(from: form.submittedAt)
                
                // Initialize if needed
                if monthlyData[monthKey] == nil {
                    monthlyData[monthKey] = (sales: 0, lotterySales: 0, payroll: 0, expenses: 0)
                }
                
                // Extract sale amount
                if let amountString = form.formData["amount"] ?? form.formData["sale"] ?? form.formData["total"],
                   let amount = Double(amountString) {
                    monthlyData[monthKey]?.lotterySales += amount
                }
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
                
                monthlyStats.append(MonthlyStats(
                    id: monthKey,
                    year: year,
                    month: month,
                    monthName: monthName,
                    sales: data.sales,
                    lotterySales: data.lotterySales,
                    payroll: data.payroll,
                    expenses: data.expenses
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
}

