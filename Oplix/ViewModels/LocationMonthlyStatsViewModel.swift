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

    private let booksService = BooksService.shared
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
            let location = try await firebaseService.fetchLocation(userId: userId, locationId: locationId)
            let hasGasStation = location.hasGasStation
            let payloads = try await booksService.loadAllMonths(userId: userId, locationId: locationId)

            let calendar = Calendar.current
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            let dayNameFormatter = DateFormatter()
            dayNameFormatter.dateFormat = "EEEE"

            var monthlyStats: [MonthlyStats] = []

            for payload in payloads {
                let aggregate = BooksAggregator.aggregateMonth(
                    monthId: payload.monthId,
                    month: payload.month,
                    daysById: payload.daysById,
                    hasGasStation: hasGasStation
                )

                guard aggregateHasData(aggregate, payload: payload) else { continue }

                let components = payload.monthId.split(separator: "-")
                guard components.count == 2,
                      let year = Int(components[0]),
                      let month = Int(components[1]) else { continue }

                let date = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
                let monthName = monthFormatter.string(from: date)

                let dailyStats = aggregate.dailySeries.map { point in
                    DailyStats(
                        id: point.dayId,
                        date: point.date,
                        dayName: dayNameFormatter.string(from: point.date),
                        sales: point.sales,
                        expenses: point.expenses,
                        fuelGallons: point.fuelGallons,
                        fuelDollars: point.fuelDollars
                    )
                }

                monthlyStats.append(
                    MonthlyStats(
                        id: payload.monthId,
                        year: year,
                        month: month,
                        monthName: monthName,
                        sales: aggregate.sales,
                        lotterySales: aggregate.lotteryCash,
                        payroll: aggregate.payrollTotal,
                        expenses: aggregate.expenses,
                        dailyStats: dailyStats
                    )
                )
            }

            monthlyStats.sort { lhs, rhs in
                if lhs.year != rhs.year { return lhs.year > rhs.year }
                return lhs.month > rhs.month
            }

            let groupedByYear = Dictionary(grouping: monthlyStats, by: { $0.year })
            yearlyStats = groupedByYear.map { year, stats in
                YearlyStats(id: year, year: year, monthlyStats: stats.sorted { lhs, rhs in
                    if lhs.year != rhs.year { return lhs.year > rhs.year }
                    return lhs.month > rhs.month
                })
            }.sorted { $0.year > $1.year }

            let currentYear = calendar.component(.year, from: Date())
            expandedYears.insert(currentYear)
        } catch {
            errorMessage = "Failed to load Daily books: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func aggregateHasData(_ aggregate: BooksMonthAggregate, payload: BooksMonthPayload) -> Bool {
        if !payload.daysById.isEmpty { return true }
        if aggregate.sales != 0 || aggregate.expenses != 0 || aggregate.lotteryCash != 0 { return true }
        return !payload.month.utilities.isEmpty ||
            !payload.month.payrollLines.isEmpty ||
            payload.month.payroll.week1 != 0 ||
            payload.month.payroll.week2 != 0 ||
            payload.month.payroll.week3 != 0 ||
            payload.month.payroll.week4 != 0 ||
            !payload.month.receivables.isEmpty
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
