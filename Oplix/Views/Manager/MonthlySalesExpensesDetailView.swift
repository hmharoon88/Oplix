//
//  MonthlySalesExpensesDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct MonthlySalesExpensesDetailView: View {
    let monthly: MonthlySalesExpenses
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var dailyData: [DailySalesExpenses] = []
    
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthly.date)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Month Header
                        VStack(spacing: 8) {
                            Text(monthString)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text("\(monthly.shiftCount) shift\(monthly.shiftCount == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Monthly Summary
                        MonthlySummaryCard(
                            totalSales: monthly.totalSales,
                            totalExpenses: monthly.totalExpenses,
                            netTotal: monthly.totalSales - monthly.totalExpenses
                        )
                        .padding(.horizontal)
                        
                        // Daily Breakdown
                        if dailyData.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "chart.bar")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No daily data available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Daily Breakdown")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                
                                ForEach(dailyData, id: \.date) { daily in
                                    DailySalesExpensesCard(daily: daily)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Month Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDailyData()
            }
        }
    }
    
    private func loadDailyData() async {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: monthly.date)
        let targetYear = calendar.component(.year, from: monthly.date)
        
        // Get all completed shifts for this month
        let completedShifts = viewModel.shifts.filter { shift in
            guard let clockOutTime = shift.clockOutTime else { return false }
            let month = calendar.component(.month, from: clockOutTime)
            let year = calendar.component(.year, from: clockOutTime)
            return month == targetMonth && year == targetYear
        }
        
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
        }.sorted { $0.date > $1.date }
    }
}

