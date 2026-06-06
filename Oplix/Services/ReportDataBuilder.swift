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
            let sales = (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
            let expenses = shift.expenses.reduce(0) { $0 + $1.amount }
            totalSales += sales
            totalExpenses += expenses
            if let overShort = shift.overShort {
                totalOverShort += overShort
            }

            shiftRows.append(RegisterShiftRow(
                id: shift.id,
                clockOut: shift.clockOutTime ?? shift.clockInTime ?? Date(),
                employeeName: employeeById[shift.employeeId]?.name ?? "—",
                sales: sales,
                expenses: expenses,
                overShort: shift.overShort
            ))
        }

        let byDay = Dictionary(grouping: filtered) { shift -> Date in
            calendar.startOfDay(for: shift.clockOutTime ?? Date())
        }

        let dailyRows: [RegisterDailyRow] = byDay.map { day, dayShifts in
            let sales = dayShifts.compactMap { ($0.cashSale ?? 0) + ($0.creditCard ?? 0) }.reduce(0, +)
            let expenses = dayShifts.flatMap(\.expenses).reduce(0) { $0 + $1.amount }
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
}
