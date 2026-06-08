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
    let lotterySales: Double
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
            async let locationTask = firebaseService.fetchLocation(userId: userId, locationId: locationId)
            async let booksTask = booksService.loadAllMonths(userId: userId, locationId: locationId)
            async let lotteryFormsTask = firebaseService.fetchLotteryForms(userId: userId, locationId: locationId)

            let location = try await locationTask
            let hasGasStation = location.hasGasStation
            let payloads = try await booksTask
            let lotteryForms = try await lotteryFormsTask
            let lotterySalesByMonth = Self.lotterySoldAmountByMonth(from: lotteryForms)
            let lotterySalesByDay = Self.lotterySoldAmountByDay(from: lotteryForms)

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
                    let appLottery = lotterySalesByDay[point.dayId] ?? 0
                    return DailyStats(
                        id: point.dayId,
                        date: point.date,
                        dayName: dayNameFormatter.string(from: point.date),
                        sales: point.sales,
                        expenses: point.expenses,
                        fuelGallons: point.fuelGallons,
                        fuelDollars: point.fuelDollars,
                        lotterySales: appLottery > 0 ? appLottery : point.lotteryCash
                    )
                }

                monthlyStats.append(
                    MonthlyStats(
                        id: payload.monthId,
                        year: year,
                        month: month,
                        monthName: monthName,
                        sales: aggregate.sales,
                        lotterySales: Self.resolvedLotterySales(
                            monthId: payload.monthId,
                            booksLotteryCash: aggregate.lotteryCash,
                            lotterySalesByMonth: lotterySalesByMonth
                        ),
                        payroll: aggregate.payrollTotal,
                        expenses: aggregate.expenses,
                        dailyStats: dailyStats
                    )
                )
            }

            let existingMonthIds = Set(monthlyStats.map(\.id))
            for (monthId, appLotterySales) in lotterySalesByMonth where appLotterySales > 0 && !existingMonthIds.contains(monthId) {
                let components = monthId.split(separator: "-")
                guard components.count == 2,
                      let year = Int(components[0]),
                      let month = Int(components[1]) else { continue }

                let date = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
                monthlyStats.append(
                    MonthlyStats(
                        id: monthId,
                        year: year,
                        month: month,
                        monthName: monthFormatter.string(from: date),
                        sales: 0,
                        lotterySales: appLotterySales,
                        payroll: 0,
                        expenses: 0,
                        dailyStats: []
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

    private static func lotterySoldAmount(from form: LotteryForm) -> Double? {
        if let summary = form.shiftSummary {
            return summary.totalSoldAmount
        }
        if let amountString = form.formData["amount"] ?? form.formData["sale"] ?? form.formData["total"],
           let amount = Double(amountString) {
            return amount
        }
        return nil
    }

    /// Sold amount from employee lottery closes, grouped by `YYYY-MM-DD`.
    private static func lotterySoldAmountByDay(from forms: [LotteryForm]) -> [String: Double] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        var byDay: [String: Double] = [:]
        for form in forms {
            guard let sold = lotterySoldAmount(from: form) else { continue }
            let dayId = formatter.string(from: form.submittedAt)
            byDay[dayId, default: 0] += sold
        }
        return byDay
    }

    /// Sold amount from employee lottery closes in the app (`shiftSummary.totalSoldAmount`),
    /// grouped by `YYYY-MM`. Matches Home Month-to-Date lottery sales.
    private static func lotterySoldAmountByMonth(from forms: [LotteryForm]) -> [String: Double] {
        let calendar = Calendar.current
        var byMonth: [String: Double] = [:]

        for form in forms {
            guard let sold = lotterySoldAmount(from: form) else { continue }

            let year = calendar.component(.year, from: form.submittedAt)
            let month = calendar.component(.month, from: form.submittedAt)
            let monthId = String(format: "%04d-%02d", year, month)
            byMonth[monthId, default: 0] += sold
        }

        return byMonth
    }

    /// Prefer app lottery sold amount when employees closed shifts in Oplix;
    /// fall back to Daily Books lottery cash for web-only entry.
    private static func resolvedLotterySales(
        monthId: String,
        booksLotteryCash: Double,
        lotterySalesByMonth: [String: Double]
    ) -> Double {
        let appLottery = lotterySalesByMonth[monthId] ?? 0
        if appLottery > 0 { return appLottery }
        return booksLotteryCash
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
