//
//  LocationMonthlyStatsView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LocationMonthlyStatsView: View {
    let userId: String
    let locationId: String
    let locationName: String
    @StateObject private var viewModel: LocationMonthlyStatsViewModel
    @Environment(\.dismiss) var dismiss
    
    init(userId: String, locationId: String, locationName: String) {
        self.userId = userId
        self.locationId = locationId
        self.locationName = locationName
        _viewModel = StateObject(wrappedValue: LocationMonthlyStatsViewModel(userId: userId, locationId: locationId, locationName: locationName))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                        Text("Oplix")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.15, green: 0.4, blue: 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Content
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else if viewModel.yearlyStats.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No Daily books data yet")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Enter data on the web dashboard under Daily books.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Location Name Header
                                Text(viewModel.locationName)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                                
                                // Yearly Stats
                                ForEach(viewModel.yearlyStats) { yearlyStat in
                                    YearlyStatsSection(
                                        yearlyStat: yearlyStat,
                                        isExpanded: viewModel.expandedYears.contains(yearlyStat.year),
                                        viewModel: viewModel,
                                        onToggle: {
                                            viewModel.toggleYear(yearlyStat.year)
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.clear]
                appearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
            .task {
                await viewModel.loadMonthlyStats()
            }
        }
    }
}

struct YearlyStatsSection: View {
    let yearlyStat: YearlyStats
    let isExpanded: Bool
    @ObservedObject var viewModel: LocationMonthlyStatsViewModel
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Year Header (Collapsible)
            Button(action: onToggle) {
                HStack {
                    Text(String(yearlyStat.year))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    // Year Totals
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatCurrency(yearlyStat.totalSales))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        Text("Total Sales")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding()
                .background(Theme.cloudWhite)
                .cornerRadius(12)
            }
            
            // Monthly Stats (Expandable)
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(yearlyStat.monthlyStats) { monthlyStat in
                        MonthlyStatsRow(monthlyStat: monthlyStat, viewModel: viewModel)
                    }
                }
                .padding(.top, 8)
            }
        }
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

struct MonthlyStatsRow: View {
    let monthlyStat: MonthlyStats
    @ObservedObject var viewModel: LocationMonthlyStatsViewModel
    
    private var isExpanded: Bool {
        viewModel.expandedMonths.contains(monthlyStat.id)
    }
    
    private var hasFuelSales: Bool {
        monthlyStat.dailyStats.contains { $0.fuelGallons > 0 || $0.fuelDollars > 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Month Name Header (Clickable to expand/collapse)
            Button(action: {
                viewModel.toggleMonth(monthlyStat.id)
            }) {
                HStack {
                    Text(monthlyStat.monthName)
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            
            // Stats Grid (Summary)
            VStack(spacing: 8) {
                StatRow(
                    icon: "dollarsign.circle.fill",
                    label: "Sales",
                    value: formatCurrency(monthlyStat.sales),
                    color: .blue
                )
                
                StatRow(
                    icon: "ticket.fill",
                    label: "Lottery Sales",
                    value: formatCurrency(monthlyStat.lotterySales),
                    color: .purple
                )
                
                StatRow(
                    icon: "banknote.fill",
                    label: "Payroll",
                    value: formatCurrency(monthlyStat.payroll),
                    color: .green
                )
                
                StatRow(
                    icon: "arrow.down.circle.fill",
                    label: "Expenses",
                    value: formatCurrency(monthlyStat.expenses),
                    color: .red
                )
            }
            
            // Daily Table (Expandable)
            if isExpanded && !monthlyStat.dailyStats.isEmpty {
                DailyStatsTable(dailyStats: monthlyStat.dailyStats, hasFuelSales: hasFuelSales)
                    .padding(.top, 8)
            }
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

struct DailyStatsTable: View {
    let dailyStats: [DailyStats]
    let hasFuelSales: Bool
    
    private var totals: (sales: Double, expenses: Double, fuelGallons: Double, fuelDollars: Double) {
        dailyStats.reduce((0, 0, 0, 0)) { result, stat in
            (result.0 + stat.sales, result.1 + stat.expenses, result.2 + stat.fuelGallons, result.3 + stat.fuelDollars)
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 8) {
                Text("Date/Day")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(width: 80, alignment: .leading)
                
                Text("Sales")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text("Expenses")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                if hasFuelSales {
                    Text("Gallons")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Text("Dollars")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Table Rows
            ForEach(dailyStats) { stat in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateFormatter.string(from: stat.date))
                            .font(.caption)
                            .foregroundColor(.black)
                        Text(stat.dayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)
                    
                    Text(formatCurrency(stat.sales))
                        .font(.caption)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Text(formatCurrency(stat.expenses))
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    if hasFuelSales {
                        Text(stat.fuelGallons > 0 ? String(format: "%.2f", stat.fuelGallons) : "-")
                            .font(.caption)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        
                        Text(stat.fuelDollars > 0 ? formatCurrency(stat.fuelDollars) : "-")
                            .font(.caption)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                
                Divider()
            }
            
            // Total Row
            HStack(spacing: 8) {
                Text("Total")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(width: 80, alignment: .leading)
                
                Text(formatCurrency(totals.sales))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text(formatCurrency(totals.expenses))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                if hasFuelSales {
                    Text(totals.fuelGallons > 0 ? String(format: "%.2f", totals.fuelGallons) : "-")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Text(totals.fuelDollars > 0 ? formatCurrency(totals.fuelDollars) : "-")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.blue.opacity(0.1))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
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

#Preview {
    LocationMonthlyStatsView(userId: "test", locationId: "test", locationName: "Test Location")
}

