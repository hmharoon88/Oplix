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
                            Text("No data available")
                                .font(.title2)
                                .foregroundColor(.secondary)
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
                    
                    // Colored Footer
                    HStack {
                        Spacer()
                        Text("© 2025 Oplix")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
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
                        MonthlyStatsRow(monthlyStat: monthlyStat)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Month Name
            Text(monthlyStat.monthName)
                .font(.headline)
                .foregroundColor(.black)
            
            // Stats Grid
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

#Preview {
    LocationMonthlyStatsView(userId: "test", locationId: "test", locationName: "Test Location")
}

