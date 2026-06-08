//
//  BooksAggregator.swift
//  Oplix
//
//  Swift port of web Daily books month aggregation (read-only).
//

import Foundation

enum BooksAggregator {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    static func aggregateMonth(
        monthId: String,
        month: BooksMonthDoc,
        daysById: [String: BooksDayDoc],
        hasGasStation: Bool
    ) -> BooksMonthAggregate {
        var lotteryCash = 0.0
        var dailySeries: [BooksDailySeriesPoint] = []
        var registerCard = 0.0
        var registerCash = 0.0
        var merchSale = 0.0
        var cashExpense = 0.0
        var checksAch = 0.0
        var otherExpense = 0.0

        for day in daysById.values.sorted(by: { $0.dayId < $1.dayId }) {
            let reg = registerDayTotal(day)
            let lot = lotteryDayTotal(day)
            let fuel = day.fuelSale
            let dayCash = sumLines(day.cashExpenses)
            let dayChecks = sumLines(day.checksAch)
            let dayOther = sumLines(day.otherExpenses)

            registerCard += reg.card
            registerCash += reg.cash
            merchSale += day.merchSale
            lotteryCash += lot.cash
            cashExpense += dayCash
            checksAch += dayChecks
            otherExpense += dayOther

            let sales = daySales(for: day, hasGasStation: hasGasStation)
            let date = dayFormatter.date(from: day.dayId) ?? Date()

            dailySeries.append(
                BooksDailySeriesPoint(
                    dayId: day.dayId,
                    date: date,
                    sales: sales,
                    expenses: dayCash + dayChecks + dayOther,
                    fuelGallons: fuel.gallons,
                    fuelDollars: fuel.dollars,
                    lotteryCash: lot.cash
                )
            )
        }

        let utilitiesTotal = month.utilities.values.reduce(0, +)
        let payrollTotal = payrollTotal(from: month)
        let sales = hasGasStation ? merchSale : registerCard + registerCash
        let expenses =
            cashExpense +
            checksAch +
            otherExpense +
            utilitiesTotal +
            payrollTotal +
            month.salesTax +
            month.accountant

        return BooksMonthAggregate(
            monthId: monthId,
            sales: sales,
            lotteryCash: lotteryCash,
            payrollTotal: payrollTotal,
            expenses: expenses,
            dailySeries: dailySeries
        )
    }

    struct MonthToDateSlice {
        let sales: Double
        let expenses: Double
        let fuelGallons: Double
        let fuelDollars: Double
        let lotteryCash: Double
    }

    /// Sums Daily books daily rows from the start of the month through `endDate` (inclusive).
    static func monthToDateSlice(
        from aggregate: BooksMonthAggregate,
        through endDate: Date,
        calendar: Calendar = .current
    ) -> MonthToDateSlice {
        let endDay = calendar.startOfDay(for: endDate)
        var sales = 0.0
        var expenses = 0.0
        var fuelGallons = 0.0
        var fuelDollars = 0.0
        var lotteryCash = 0.0

        for point in aggregate.dailySeries {
            let day = calendar.startOfDay(for: point.date)
            guard day <= endDay else { continue }
            sales += point.sales
            expenses += point.expenses
            fuelGallons += point.fuelGallons
            fuelDollars += point.fuelDollars
            lotteryCash += point.lotteryCash
        }

        return MonthToDateSlice(
            sales: sales,
            expenses: expenses,
            fuelGallons: fuelGallons,
            fuelDollars: fuelDollars,
            lotteryCash: lotteryCash
        )
    }

    private static func registerDayTotal(_ day: BooksDayDoc) -> (card: Double, cash: Double, overShort: Double) {
        let r1 = registerBlockTotal(day.register1)
        let r2 = registerBlockTotal(day.register2)
        return (
            card: r1.card + r2.card,
            cash: r1.cash + r2.cash,
            overShort: r1.overShort + r2.overShort
        )
    }

    private static func registerBlockTotal(_ block: BooksRegisterUnit) -> (card: Double, cash: Double, overShort: Double) {
        (
            card: block.shift1.cardSale + block.shift2.cardSale,
            cash: block.shift1.cashSale + block.shift2.cashSale,
            overShort: block.shift1.overShort + block.shift2.overShort
        )
    }

    private static func lotteryDayTotal(_ day: BooksDayDoc) -> (cash: Double, overShort: Double) {
        (
            cash: day.lottery.shift1.cash + day.lottery.shift2.cash,
            overShort: day.lottery.shift1.overShort + day.lottery.shift2.overShort
        )
    }

    private static func daySales(for day: BooksDayDoc, hasGasStation: Bool) -> Double {
        if hasGasStation {
            return day.merchSale
        }
        let reg = registerDayTotal(day)
        return reg.card + reg.cash
    }

    private static func sumLines(_ lines: [BooksLineItem]) -> Double {
        lines.reduce(0) { $0 + $1.amount }
    }

    private static func payrollTotal(from month: BooksMonthDoc) -> Double {
        if !month.payrollLines.isEmpty {
            return month.payrollLines.reduce(0) { $0 + $1.pay }
        }
        return month.payroll.week1 + month.payroll.week2 + month.payroll.week3 + month.payroll.week4
    }
}
