//
//  PayrollScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct PayrollScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var weeklyPayrolls: [WeeklyPayroll] = []
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Loading payroll data...")
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Separate current week and previous weeks
                        let (currentWeek, previousWeeks) = separateCurrentAndPreviousWeeks()
                        
                        // Current Week Section
                        if let currentWeek = currentWeek {
                            WeeklyPayrollSection(
                                title: "Current Week",
                                weekRange: currentWeek.weekRange,
                                payroll: currentWeek
                            )
                        }
                        
                        // Previous Weeks Section
                        if !previousWeeks.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Previous Weeks")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                
                                ForEach(previousWeeks, id: \.weekRange) { payroll in
                                    WeeklyPayrollSection(
                                        title: payroll.weekRange,
                                        weekRange: payroll.weekRange,
                                        payroll: payroll
                                    )
                                }
                            }
                        }
                        
                        // Show message if no data
                        if currentWeek == nil && previousWeeks.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "dollarsign.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text("No Payroll Data")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Payroll information will appear here once employees complete shifts.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical, 60)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Payroll")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPayrollData()
        }
    }
    
    private func loadPayrollData() async {
        isLoading = true
        defer { isLoading = false }
        
        // Get all completed shifts
        let completedShifts = viewModel.shifts.filter { $0.isCompleted }
        
        // Group shifts by week
        let calendar = Calendar.current
        let groupedShifts = Dictionary(grouping: completedShifts) { shift -> String in
            guard let clockOutTime = shift.clockOutTime else {
                return "Unknown"
            }
            let weekOfYear = calendar.component(.weekOfYear, from: clockOutTime)
            let year = calendar.component(.year, from: clockOutTime)
            return "\(year)-W\(weekOfYear)"
        }
        
        // Calculate payroll for each week
        var payrolls: [WeeklyPayroll] = []
        
        for (weekKey, shifts) in groupedShifts {
            // Get week range
            guard let firstShift = shifts.first(where: { $0.clockOutTime != nil }),
                  let clockOutTime = firstShift.clockOutTime else { continue }
            
            let weekRange = getWeekRange(for: clockOutTime)
            
            // Group shifts by employee
            let shiftsByEmployee = Dictionary(grouping: shifts, by: { $0.employeeId })
            
            var employeePayrolls: [EmployeePayroll] = []
            
            for (employeeId, employeeShifts) in shiftsByEmployee {
                guard let employee = viewModel.employees.first(where: { $0.id == employeeId }) else { continue }
                
                // Calculate total hours for this employee in this week
                let totalHours = employeeShifts.compactMap { $0.hoursWorked }.reduce(0, +)
                
                // Get hourly rate (default to 0 if not set)
                let hourlyRate = employee.hourlyRate ?? 0.0
                
                // Calculate pay
                let pay = totalHours * hourlyRate
                
                employeePayrolls.append(EmployeePayroll(
                    employeeId: employeeId,
                    employeeName: employee.name,
                    hours: totalHours,
                    payRate: hourlyRate,
                    pay: pay
                ))
            }
            
            // Sort by employee name
            employeePayrolls.sort { $0.employeeName < $1.employeeName }
            
            payrolls.append(WeeklyPayroll(
                weekRange: weekRange,
                employeePayrolls: employeePayrolls
            ))
        }
        
        // Sort by week (most recent first)
        payrolls.sort { week1, week2 in
            // Extract year and week number for comparison
            let components1 = week1.weekRange.split(separator: " ").last?.split(separator: "-") ?? []
            let components2 = week2.weekRange.split(separator: " ").last?.split(separator: "-") ?? []
            
            guard components1.count >= 2, components2.count >= 2,
                  let year1 = Int(components1[0]), let week1 = Int(components1[1]),
                  let year2 = Int(components2[0]), let week2 = Int(components2[1]) else {
                return false
            }
            
            if year1 != year2 {
                return year1 > year2
            }
            return week1 > week2
        }
        
        weeklyPayrolls = payrolls
    }
    
    private func getWeekRange(for date: Date) -> String {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startString = formatter.string(from: startOfWeek)
        let endString = formatter.string(from: endOfWeek)
        
        let year = calendar.component(.year, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        
        return "\(startString) - \(endString), \(year) (Week \(week))"
    }
    
    private func separateCurrentAndPreviousWeeks() -> (currentWeek: WeeklyPayroll?, previousWeeks: [WeeklyPayroll]) {
        let calendar = Calendar.current
        let now = Date()
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        var current: WeeklyPayroll? = nil
        var previous: [WeeklyPayroll] = []
        
        for payroll in weeklyPayrolls {
            if isCurrentWeek(weekRange: payroll.weekRange, currentWeek: currentWeek, currentYear: currentYear) {
                current = payroll
            } else {
                previous.append(payroll)
            }
        }
        
        return (current, previous)
    }
    
    private func isCurrentWeek(weekRange: String, currentWeek: Int, currentYear: Int) -> Bool {
        // Extract week and year from weekRange string
        // Format: "MMM d - MMM d, YYYY (Week W)"
        if let weekMatch = weekRange.range(of: "Week \\d+", options: .regularExpression) {
            let weekString = String(weekRange[weekMatch]).replacingOccurrences(of: "Week ", with: "")
            if let week = Int(weekString) {
                // Extract year from the string
                if let yearMatch = weekRange.range(of: "\\d{4}", options: .regularExpression) {
                    let yearString = String(weekRange[yearMatch])
                    if let year = Int(yearString) {
                        return week == currentWeek && year == currentYear
                    }
                }
            }
        }
        return false
    }
}

struct WeeklyPayrollSection: View {
    let title: String
    let weekRange: String
    let payroll: WeeklyPayroll
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Text(weekRange)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if payroll.employeePayrolls.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No payroll data for this week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(payroll.employeePayrolls, id: \.employeeId) { employeePayroll in
                        EmployeePayrollRow(payroll: employeePayroll)
                    }
                }
                
                // Total for the week
                Divider()
                    .padding(.vertical, 8)
                
                HStack {
                    Text("Week Total")
                        .font(.headline)
                        .foregroundColor(.black)
                    Spacer()
                    Text(formatCurrency(payroll.totalPay))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct EmployeePayrollRow: View {
    let payroll: EmployeePayroll
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(payroll.employeeName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                
                HStack(spacing: 16) {
                    Text("\(String(format: "%.1f", payroll.hours)) hrs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if payroll.payRate > 0 {
                        Text("@ \(formatCurrency(payroll.payRate))/hr")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(formatCurrency(payroll.pay))
                .font(.body)
                .fontWeight(.bold)
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

// MARK: - Data Models
struct WeeklyPayroll {
    let weekRange: String
    let employeePayrolls: [EmployeePayroll]
    
    var totalPay: Double {
        employeePayrolls.reduce(0) { $0 + $1.pay }
    }
}

struct EmployeePayroll {
    let employeeId: String
    let employeeName: String
    let hours: Double
    let payRate: Double
    let pay: Double
}

