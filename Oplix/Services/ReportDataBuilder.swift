//
//  ReportDataBuilder.swift
//  Oplix
//

import Foundation

enum ReportDataBuilder {
    static func isInRange(_ date: Date, interval: ReportDateInterval) -> Bool {
        date >= interval.start && date <= interval.end
    }

    // MARK: - Lottery

    static func buildLotteryReport(
        forms: [LotteryForm],
        shifts: [Shift],
        employees: [Employee],
        interval: ReportDateInterval
    ) -> LotteryReportContent {
        let shiftById = Dictionary(uniqueKeysWithValues: shifts.map { ($0.id, $0) })
        let employeeById = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })

        let filtered = forms
            .filter { isInRange($0.submittedAt, interval: interval) }
            .filter { $0.shiftSummary != nil }
            .sorted { $0.submittedAt > $1.submittedAt }

        var rows: [LotteryReportRow] = []
        var totalSold = 0.0
        var totalExpected = 0.0
        var totalActual = 0.0
        var netOverShort = 0.0

        for form in filtered {
            guard let summary = form.shiftSummary else { continue }
            let shift = shiftById[form.shiftId]
            let employeeName = shift.flatMap { employeeById[$0.employeeId]?.name } ?? "—"
            let sold = summary.totalSoldAmount
            let expected = summary.cashInBagNet
            let actual = summary.actualEnclosedCash
            let overShort = summary.overShort

            totalSold += sold
            totalExpected += expected
            if let actual {
                totalActual += actual
            }
            if let overShort {
                netOverShort += overShort
            }

            let terminal = form.effectiveTerminalNumber
            let terminalLabel = terminal > 1 ? "Terminal \(terminal)" : "Terminal 1"

            rows.append(LotteryReportRow(
                id: form.id,
                submittedAt: form.submittedAt,
                terminalLabel: terminalLabel,
                employeeName: employeeName,
                sold: sold,
                expectedEnclosed: expected,
                actualEnclosed: actual,
                overShort: overShort
            ))
        }

        let employeeSections = buildLotteryEmployeeSections(from: rows)

        return LotteryReportContent(
            summary: LotteryReportSummary(
                closeCount: rows.count,
                totalSold: totalSold,
                totalExpectedEnclosed: totalExpected,
                totalActualEnclosed: totalActual,
                netOverShort: netOverShort
            ),
            rows: rows,
            employeeSections: employeeSections
        )
    }

    private static func buildLotteryEmployeeSections(from rows: [LotteryReportRow]) -> [LotteryEmployeeSection] {
        let grouped = Dictionary(grouping: rows) { $0.employeeName }
        return grouped.map { name, employeeRows in
            let sorted = employeeRows.sorted { $0.submittedAt > $1.submittedAt }
            let netOS = sorted.compactMap(\.overShort).reduce(0, +)
            return LotteryEmployeeSection(
                id: name,
                employeeName: name,
                closeCount: sorted.count,
                totalSold: sorted.reduce(0) { $0 + $1.sold },
                netOverShort: netOS,
                rows: sorted
            )
        }
        .sorted { $0.totalSold > $1.totalSold }
    }

    // MARK: - Payroll

    static func buildPayrollReport(
        shifts: [Shift],
        employees: [Employee],
        interval: ReportDateInterval
    ) -> PayrollReportContent {
        let employeeById = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })

        let filtered = shifts.filter { shift in
            guard let clockOut = shift.clockOutTime else { return false }
            return isInRange(clockOut, interval: interval)
        }

        let grouped = Dictionary(grouping: filtered) { $0.employeeId }
        var rows: [PayrollReportRow] = []

        for (employeeId, employeeShifts) in grouped {
            guard let employee = employeeById[employeeId],
                  let rate = employee.hourlyRate,
                  rate > 0 else { continue }

            let hours = employeeShifts.compactMap(\.hoursWorked).reduce(0, +)
            let pay = hours * rate
            rows.append(PayrollReportRow(
                id: employeeId,
                employeeName: employee.name,
                hourlyRate: rate,
                hours: hours,
                pay: pay,
                shiftCount: employeeShifts.count
            ))
        }

        rows.sort { $0.pay > $1.pay }

        let totalHours = rows.reduce(0) { $0 + $1.hours }
        let totalPay = rows.reduce(0) { $0 + $1.pay }
        let shiftCount = filtered.count

        let employeeSections = rows.map { row in
            PayrollEmployeeSection(
                id: row.id,
                employeeName: row.employeeName,
                hourlyRate: row.hourlyRate,
                hours: row.hours,
                pay: row.pay,
                shiftCount: row.shiftCount
            )
        }

        return PayrollReportContent(
            summary: PayrollReportSummary(
                employeeCount: rows.count,
                totalHours: totalHours,
                totalPay: totalPay,
                shiftCount: shiftCount
            ),
            rows: rows,
            employeeSections: employeeSections
        )
    }

    // MARK: - Register / sales & expenses

    static func isDayInRange(_ day: Date, interval: ReportDateInterval, calendar: Calendar = .current) -> Bool {
        let normalized = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        return normalized >= start && normalized <= end
    }

    /// Sales, expenses, and over/short for one shift (supports multi-register shifts).
    static func shiftRegisterTotals(_ shift: Shift) -> (sales: Double, expenses: Double, overShort: Double?) {
        var sales = 0.0
        var expenses = shift.expenses.reduce(0) { $0 + $1.amount }
        var overShortSum = 0.0
        var hasOverShort = false

        if !shift.registers.isEmpty {
            for register in shift.registers {
                sales += (register.cashSale ?? 0) + (register.creditCard ?? 0)
                if let amounts = register.cashExpenseAmounts {
                    expenses += amounts.reduce(0, +)
                } else if let amount = register.cashExpense {
                    expenses += amount
                }
                if let overShort = register.overShort {
                    overShortSum += overShort
                    hasOverShort = true
                }
            }
            return (sales, expenses, hasOverShort ? overShortSum : shift.overShort)
        }

        sales = (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
        return (sales, expenses, shift.overShort)
    }

    static func buildRegisterReport(
        shifts: [Shift],
        employees: [Employee],
        interval: ReportDateInterval,
        calendar: Calendar = .current
    ) -> RegisterReportContent {
        let employeeById = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })

        let filtered = shifts.filter { shift in
            guard shift.isCompleted,
                  let clockOut = shift.clockOutTime,
                  shift.hasRegisterData else { return false }
            return isInRange(clockOut, interval: interval)
        }

        var totalSales = 0.0
        var totalExpenses = 0.0
        var totalOverShort = 0.0
        var shiftRows: [RegisterShiftRow] = []

        for shift in filtered.sorted(by: { ($0.clockOutTime ?? .distantPast) > ($1.clockOutTime ?? .distantPast) }) {
            let totals = shiftRegisterTotals(shift)
            totalSales += totals.sales
            totalExpenses += totals.expenses
            if let overShort = totals.overShort {
                totalOverShort += overShort
            }

            shiftRows.append(RegisterShiftRow(
                id: shift.id,
                clockOut: shift.clockOutTime ?? shift.clockInTime ?? Date(),
                employeeName: employeeById[shift.employeeId]?.name ?? "—",
                sales: totals.sales,
                expenses: totals.expenses,
                overShort: totals.overShort
            ))
        }

        let byDay = Dictionary(grouping: filtered) { shift -> Date in
            calendar.startOfDay(for: shift.clockOutTime ?? Date())
        }

        let dailyRows: [RegisterDailyRow] = byDay.map { day, dayShifts in
            var sales = 0.0
            var expenses = 0.0
            for shift in dayShifts {
                let totals = shiftRegisterTotals(shift)
                sales += totals.sales
                expenses += totals.expenses
            }
            return RegisterDailyRow(
                id: ISO8601DateFormatter().string(from: day),
                date: day,
                sales: sales,
                expenses: expenses,
                shiftCount: dayShifts.count
            )
        }.sorted { $0.date > $1.date }

        let employeeSections = buildRegisterEmployeeSections(from: shiftRows)

        return RegisterReportContent(
            summary: RegisterReportSummary(
                totalSales: totalSales,
                totalExpenses: totalExpenses,
                netTotal: totalSales - totalExpenses,
                shiftCount: filtered.count,
                totalOverShort: totalOverShort
            ),
            dailyRows: dailyRows,
            shiftRows: shiftRows,
            employeeSections: employeeSections
        )
    }

    private static func buildRegisterEmployeeSections(from shiftRows: [RegisterShiftRow]) -> [RegisterEmployeeSection] {
        let grouped = Dictionary(grouping: shiftRows) { $0.employeeName }
        return grouped.map { name, rows in
            let sorted = rows.sorted { $0.clockOut > $1.clockOut }
            let sales = sorted.reduce(0) { $0 + $1.sales }
            let expenses = sorted.reduce(0) { $0 + $1.expenses }
            let overShort = sorted.compactMap(\.overShort).reduce(0, +)
            return RegisterEmployeeSection(
                id: name,
                employeeName: name,
                shiftCount: sorted.count,
                totalSales: sales,
                totalExpenses: expenses,
                netTotal: sales - expenses,
                totalOverShort: overShort,
                shiftRows: sorted
            )
        }
        .sorted { $0.totalSales > $1.totalSales }
    }

    /// Daily totals from web Daily books for the selected date range.
    static func buildRegisterReportFromBooks(
        payloads: [BooksMonthPayload],
        interval: ReportDateInterval,
        hasGasStation: Bool,
        calendar: Calendar = .current
    ) -> RegisterReportContent? {
        var dailyRows: [RegisterDailyRow] = []
        var totalSales = 0.0
        var totalExpenses = 0.0

        for payload in payloads {
            let aggregate = BooksAggregator.aggregateMonth(
                monthId: payload.monthId,
                month: payload.month,
                daysById: payload.daysById,
                hasGasStation: hasGasStation
            )

            for point in aggregate.dailySeries {
                guard isDayInRange(point.date, interval: interval, calendar: calendar) else { continue }
                guard point.sales != 0 || point.expenses != 0 else { continue }

                dailyRows.append(
                    RegisterDailyRow(
                        id: point.dayId,
                        date: point.date,
                        sales: point.sales,
                        expenses: point.expenses,
                        shiftCount: 0
                    )
                )
                totalSales += point.sales
                totalExpenses += point.expenses
            }
        }

        guard !dailyRows.isEmpty else { return nil }

        dailyRows.sort { $0.date > $1.date }

        return RegisterReportContent(
            summary: RegisterReportSummary(
                totalSales: totalSales,
                totalExpenses: totalExpenses,
                netTotal: totalSales - totalExpenses,
                shiftCount: dailyRows.count,
                totalOverShort: 0
            ),
            dailyRows: dailyRows,
            shiftRows: [],
            employeeSections: []
        )
    }

    /// Prefer Daily books for location totals; keep shift rows for employee breakdown.
    static func mergeRegisterReports(
        books: RegisterReportContent?,
        shifts: RegisterReportContent
    ) -> RegisterReportContent {
        guard let books, !books.dailyRows.isEmpty else {
            return shifts
        }

        let summary = RegisterReportSummary(
            totalSales: books.summary.totalSales,
            totalExpenses: books.summary.totalExpenses,
            netTotal: books.summary.totalSales - books.summary.totalExpenses,
            shiftCount: shifts.summary.shiftCount > 0 ? shifts.summary.shiftCount : books.dailyRows.count,
            totalOverShort: shifts.summary.totalOverShort
        )

        return RegisterReportContent(
            summary: summary,
            dailyRows: books.dailyRows,
            shiftRows: shifts.shiftRows,
            employeeSections: shifts.employeeSections
        )
    }
}
