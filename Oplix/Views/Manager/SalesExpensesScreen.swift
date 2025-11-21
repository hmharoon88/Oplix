//
//  SalesExpensesScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct SalesExpensesScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var dailyData: [DailySalesExpenses] = []
    @State private var monthlyData: [MonthlySalesExpenses] = []
    @State private var isLoading = true
    @State private var selectedMonth: MonthlySalesExpenses?
    
    private var currentMonthData: [DailySalesExpenses] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        return dailyData.filter { daily in
            let month = calendar.component(.month, from: daily.date)
            let year = calendar.component(.year, from: daily.date)
            return month == currentMonth && year == currentYear
        }.sorted { $0.date > $1.date }
    }
    
    private var previousMonths: [MonthlySalesExpenses] {
        monthlyData.filter { monthly in
            let calendar = Calendar.current
            let now = Date()
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            let month = calendar.component(.month, from: monthly.date)
            let year = calendar.component(.year, from: monthly.date)
            return !(month == currentMonth && year == currentYear)
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading sales and expenses data...")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Current Month Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Current Month")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                
                                if currentMonthData.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "chart.bar")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        Text("No data for current month")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                    .padding(.horizontal)
                                } else {
                                    // Monthly Summary
                                    let totalSales = currentMonthData.reduce(0) { $0 + $1.totalSales }
                                    let totalExpenses = currentMonthData.reduce(0) { $0 + $1.totalExpenses }
                                    
                                    MonthlySummaryCard(
                                        totalSales: totalSales,
                                        totalExpenses: totalExpenses,
                                        netTotal: totalSales - totalExpenses
                                    )
                                    .padding(.horizontal)
                                    
                                    // Daily Data
                                    ForEach(currentMonthData, id: \.date) { daily in
                                        DailySalesExpensesCard(daily: daily)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Previous Months Section
                            if !previousMonths.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Previous Months")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                        .padding(.horizontal)
                                    
                                    ForEach(previousMonths, id: \.date) { monthly in
                                        Button(action: {
                                            selectedMonth = monthly
                                        }) {
                                            MonthlyCard(monthly: monthly)
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Sales & Expenses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedMonth) { monthly in
                MonthlySalesExpensesDetailView(monthly: monthly, viewModel: viewModel)
            }
            .task {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        let completedShifts = viewModel.shifts.filter { $0.isCompleted }
        
        // Group by day
        let shiftsByDay = Dictionary(grouping: completedShifts) { shift -> Date in
            guard let clockOutTime = shift.clockOutTime else { return Date() }
            return calendar.startOfDay(for: clockOutTime)
        }
        
        // Calculate daily data
        dailyData = shiftsByDay.map { date, shifts in
            let totalSales = shifts.compactMap { shift in
                (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
            }.reduce(0, +)
            
            let totalExpenses = shifts.flatMap { $0.expenses }.reduce(0) { $0 + $1.amount }
            
            return DailySalesExpenses(
                date: date,
                totalSales: totalSales,
                totalExpenses: totalExpenses,
                shiftCount: shifts.count
            )
        }
        
        // Group by month
        let shiftsByMonth = Dictionary(grouping: completedShifts) { shift -> Date in
            guard let clockOutTime = shift.clockOutTime else { return Date() }
            let components = calendar.dateComponents([.year, .month], from: clockOutTime)
            return calendar.date(from: components) ?? Date()
        }
        
        // Calculate monthly data
        monthlyData = shiftsByMonth.map { monthDate, shifts in
            let totalSales = shifts.compactMap { shift in
                (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
            }.reduce(0, +)
            
            let totalExpenses = shifts.flatMap { $0.expenses }.reduce(0) { $0 + $1.amount }
            
            return MonthlySalesExpenses(
                date: monthDate,
                totalSales: totalSales,
                totalExpenses: totalExpenses,
                shiftCount: shifts.count
            )
        }
    }
}

// MARK: - Daily Sales Expenses Card
struct DailySalesExpensesCard: View {
    let daily: DailySalesExpenses
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: daily.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateString)
                .font(.headline)
                .foregroundColor(.black)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sales")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(daily.totalSales))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(daily.totalExpenses))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            HStack {
                Text("Net Total")
                    .font(.subheadline)
                    .foregroundColor(.black)
                Spacer()
                Text(formatCurrency(daily.totalSales - daily.totalExpenses))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor((daily.totalSales - daily.totalExpenses) >= 0 ? .green : .red)
            }
            
            Text("\(daily.shiftCount) shift\(daily.shiftCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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

// MARK: - Monthly Summary Card
struct MonthlySummaryCard: View {
    let totalSales: Double
    let totalExpenses: Double
    let netTotal: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Month Summary")
                .font(.headline)
                .foregroundColor(.black)
            
            HStack(spacing: 30) {
                VStack(spacing: 4) {
                    Text("Total Sales")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(totalSales))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                VStack(spacing: 4) {
                    Text("Total Expenses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(totalExpenses))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            HStack {
                Text("Net Total")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Text(formatCurrency(netTotal))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(netTotal >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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

// MARK: - Monthly Card
struct MonthlyCard: View {
    let monthly: MonthlySalesExpenses
    
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthly.date)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(monthString)
                    .font(.headline)
                    .foregroundColor(.black)
                
                HStack(spacing: 16) {
                    Label(formatCurrency(monthly.totalSales), systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                    Label(formatCurrency(monthly.totalExpenses), systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Text("\(monthly.shiftCount) shift\(monthly.shiftCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
struct DailySalesExpenses: Identifiable {
    let id = UUID()
    let date: Date
    let totalSales: Double
    let totalExpenses: Double
    let shiftCount: Int
}

struct MonthlySalesExpenses: Identifiable {
    let id = UUID()
    let date: Date
    let totalSales: Double
    let totalExpenses: Double
    let shiftCount: Int
}

