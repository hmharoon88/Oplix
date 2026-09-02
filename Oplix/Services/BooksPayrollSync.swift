//
//  BooksPayrollSync.swift
//  Oplix
//
//  Merges iOS payroll runs into web Daily books month documents.
//

import Foundation

enum BooksPayrollSync {
    private static let moneyScale = 100.0

    static func weekOfMonth(dayId: String) -> String {
        let day = Int(dayId.dropFirst(8).prefix(2)) ?? 0
        if day < 1 { return "week1" }
        if day <= 7 { return "week1" }
        if day <= 14 { return "week2" }
        if day <= 21 { return "week3" }
        return "week4"
    }

    static func roundedMoney(_ value: Double) -> Double {
        (value * moneyScale).rounded() / moneyScale
    }

    /// Build the per-run sync record stored on the books month doc (`payrollRunSyncs`).
    static func syncRecord(for run: LocationPayrollRun, calendar: Calendar = .current) -> [String: Any] {
        let periodEnd = calendar.startOfDay(for: run.periodEnd)
        let dayId = BooksDateIds.dayId(from: periodEnd, calendar: calendar)
        let weekKey = weekOfMonth(dayId: dayId)

        let lines: [[String: Any]] = run.lines.map { line in
            [
                "id": line.id,
                "employeeId": line.id,
                "employeeName": line.employeeName,
                "hours": roundedMoney(line.hours),
                "hourlyRate": roundedMoney(line.hourlyRate),
                "pay": roundedMoney(line.pay),
            ]
        }

        return [
            "periodEnd": dayId,
            "weekKey": weekKey,
            "totalPay": roundedMoney(run.totalPay),
            "lines": lines,
        ]
    }

    /// Merge a payroll run into raw month Firestore data; returns fields to write (payrollRunSyncs, payrollLines, payroll).
    static func mergedMonthPayrollFields(
        existingMonthData: [String: Any],
        run: LocationPayrollRun,
        calendar: Calendar = .current
    ) -> [String: Any] {
        var payrollRunSyncs = existingMonthData["payrollRunSyncs"] as? [String: [String: Any]] ?? [:]
        payrollRunSyncs[run.id] = syncRecord(for: run, calendar: calendar)

        let rebuilt = rebuildPayroll(existingMonthData: existingMonthData, payrollRunSyncs: payrollRunSyncs)
        return [
            "payrollRunSyncs": payrollRunSyncs,
            "payrollLines": rebuilt.payrollLines,
            "payroll": rebuilt.payroll,
        ]
    }

    private struct AggregatedLine {
        var id: String
        var employeeName: String
        var hours: Double
        var hourlyRate: Double
        var pay: Double
    }

    private static func rebuildPayroll(
        existingMonthData: [String: Any],
        payrollRunSyncs: [String: [String: Any]]
    ) -> (payrollLines: [[String: Any]], payroll: [String: Double]) {
        var syncedEmployeeIds = Set<String>()
        var aggregatedByEmployee: [String: AggregatedLine] = [:]

        var payrollWeeks: [String: Double] = [
            "week1": 0,
            "week2": 0,
            "week3": 0,
            "week4": 0,
        ]

        for sync in payrollRunSyncs.values {
            let weekKey = sync["weekKey"] as? String ?? "week4"
            payrollWeeks[weekKey, default: 0] += doubleValue(sync["totalPay"])

            guard let lines = sync["lines"] as? [[String: Any]] else { continue }
            for line in lines {
                let employeeId = stringValue(line["id"]).isEmpty
                    ? stringValue(line["employeeId"])
                    : stringValue(line["id"])
                guard !employeeId.isEmpty else { continue }

                syncedEmployeeIds.insert(employeeId)
                let hours = doubleValue(line["hours"])
                let pay = doubleValue(line["pay"])
                let hourlyRate = doubleValue(line["hourlyRate"])
                let name = stringValue(line["employeeName"])

                if var existing = aggregatedByEmployee[employeeId] {
                    existing.hours += hours
                    existing.pay += pay
                    if hourlyRate > 0 { existing.hourlyRate = hourlyRate }
                    if !name.isEmpty { existing.employeeName = name }
                    aggregatedByEmployee[employeeId] = existing
                } else {
                    aggregatedByEmployee[employeeId] = AggregatedLine(
                        id: employeeId,
                        employeeName: name.isEmpty ? "Employee" : name,
                        hours: hours,
                        hourlyRate: hourlyRate,
                        pay: pay
                    )
                }
            }
        }

        for key in payrollWeeks.keys {
            payrollWeeks[key] = roundedMoney(payrollWeeks[key] ?? 0)
        }

        let existingLines = existingMonthData["payrollLines"] as? [[String: Any]] ?? []
        let preservedLines = existingLines.filter { line in
            let employeeId = stringValue(line["id"]).isEmpty
                ? stringValue(line["employeeId"])
                : stringValue(line["id"])
            return !syncedEmployeeIds.contains(employeeId)
        }

        let runLines: [[String: Any]] = aggregatedByEmployee.values
            .map { line in
                let hours = roundedMoney(line.hours)
                let pay = roundedMoney(line.pay)
                let rate = hours > 0
                    ? roundedMoney(pay / hours)
                    : roundedMoney(line.hourlyRate)
                return [
                    "id": line.id,
                    "employeeId": line.id,
                    "employeeName": line.employeeName,
                    "hours": hours,
                    "hourlyRate": rate,
                    "pay": pay,
                    "syncedFromPayrollRun": true,
                ]
            }
            .filter { doubleValue($0["pay"]) > 0 || doubleValue($0["hours"]) > 0 }
            .sorted { stringValue($0["employeeName"]).localizedCaseInsensitiveCompare(stringValue($1["employeeName"])) == .orderedAscending }

        let existingPayroll = existingMonthData["payroll"] as? [String: Any] ?? [:]
        var mergedWeeks: [String: Double] = [
            "week1": doubleValue(existingPayroll["week1"]),
            "week2": doubleValue(existingPayroll["week2"]),
            "week3": doubleValue(existingPayroll["week3"]),
            "week4": doubleValue(existingPayroll["week4"]),
        ]

        let previousSyncs = existingMonthData["payrollRunSyncs"] as? [String: [String: Any]] ?? [:]
        for sync in previousSyncs.values {
            let weekKey = sync["weekKey"] as? String ?? "week4"
            mergedWeeks[weekKey, default: 0] -= doubleValue(sync["totalPay"])
        }
        for sync in payrollRunSyncs.values {
            let weekKey = sync["weekKey"] as? String ?? "week4"
            mergedWeeks[weekKey, default: 0] += doubleValue(sync["totalPay"])
        }
        for key in mergedWeeks.keys {
            mergedWeeks[key] = roundedMoney(mergedWeeks[key] ?? 0)
        }

        // When payroll lines exist, week buckets are secondary; keep preserved-line weeks from existing doc only.
        if preservedLines.isEmpty, runLines.isEmpty {
            return (payrollLines: [], payroll: mergedWeeks)
        }

        return (payrollLines: preservedLines + runLines, payroll: mergedWeeks)
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        return String(describing: value)
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let parsed = Double(string) { return parsed }
        return 0
    }
}
