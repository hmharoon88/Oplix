//
//  MonthlySalesExpensesDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct MonthlySalesExpensesDetailView: View {
    let monthly: MonthlySalesExpenses
    let userId: String
    let locationId: String
    let hasGasStation: Bool

    @Environment(\.dismiss) var dismiss
    @State private var dailyData: [DailySalesExpenses] = []
    @State private var isLoading = true

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

                if isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            VStack(spacing: 8) {
                                Text(monthString)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)

                                Text("\(monthly.dayCount) day\(monthly.dayCount == 1 ? "" : "s") in Daily books")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.cloudWhite)
                            .cornerRadius(12)
                            .padding(.horizontal)

                            MonthlySummaryCard(
                                totalSales: monthly.totalSales,
                                totalExpenses: monthly.totalExpenses,
                                netTotal: monthly.totalSales - monthly.totalExpenses
                            )
                            .padding(.horizontal)

                            if dailyData.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "chart.bar")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    Text("No daily entries for this month")
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

                                    ForEach(dailyData) { daily in
                                        DailySalesExpensesCard(daily: daily)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
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
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await BooksService.shared.loadMonth(
                userId: userId,
                locationId: locationId,
                monthId: monthly.monthId
            )
            let aggregate = BooksAggregator.aggregateMonth(
                monthId: payload.monthId,
                month: payload.month,
                daysById: payload.daysById,
                hasGasStation: hasGasStation
            )

            dailyData = aggregate.dailySeries
                .filter { $0.sales != 0 || $0.expenses != 0 }
                .map { point in
                    DailySalesExpenses(
                        date: point.date,
                        totalSales: point.sales,
                        totalExpenses: point.expenses,
                        dayCount: 1
                    )
                }
                .sorted { $0.date > $1.date }
        } catch {
            dailyData = []
        }
    }
}
