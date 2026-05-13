//
//  LocationAlertsViewModel.swift
//  Oplix
//
//  Builds "Needs Attention" alerts for a single location, used on the
//  manager's Location Detail screen. Mirrors the per-location builders
//  in HomeAlertsViewModel.swift — when you change behavior here, keep
//  the home-screen version in sync so the two surfaces never disagree
//  about what counts as an alert.
//
//  Scope notes:
//  - Fetches are limited to this location's collection paths, plus a
//    single manager-wide pass for tasks (to find disapproved tasks) and
//    documents (since both are stored at the manager level, not under
//    the location). Results are filtered to this location.
//  - Reuses ActionAlert / AlertSeverity / ManagerAlertCategory types
//    defined in HomeAlertsViewModel.swift — no duplicate type defs.
//

import Foundation
import SwiftUI

@MainActor
final class LocationAlertsViewModel: ObservableObject {
    @Published private(set) var alerts: [ActionAlert] = []
    @Published private(set) var isLoading = false

    private let userId: String
    private let locationId: String
    private let firebaseService = FirebaseService.shared

    // Same thresholds as the home-screen view model — see comment on the
    // type for why these values were chosen.
    private let varianceThreshold: Double = 5.0
    private let varianceCriticalThreshold: Double = 20.0
    private let unclosedShiftHours: Double = 12.0
    private let varianceLookbackDays: Int = 7
    private let missingRegisterLookbackDays: Int = 7
    private let lotteryActivityWindowDays: Int = 30
    private let docExpiryWindowDays: Int = 30

    init(userId: String, locationId: String) {
        self.userId = userId
        self.locationId = locationId
    }

    func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }

        // Fan out every fetch we need for this one location.
        async let locationT = firebaseService.fetchLocation(userId: userId, locationId: locationId)
        async let shiftsT = firebaseService.fetchShifts(userId: userId, locationId: locationId)
        async let formsT = firebaseService.fetchLotteryForms(userId: userId, locationId: locationId)
        async let payablesT = firebaseService.fetchPayables(userId: userId, locationId: locationId)
        async let employeesT = firebaseService.fetchEmployees(userId: userId, locationId: locationId)
        async let docsT = firebaseService.fetchAllDocuments(userId: userId)
        async let tasksT = firebaseService.fetchManagerTasks(userId: userId)

        let location: Location
        let shifts: [Shift]
        let forms: [LotteryForm]
        let payables: [Payable]
        let locEmployees: [Employee]
        let docs: [Document]
        let tasks: [WorkTask]
        do {
            // Without a location we can't render names in subtitles, so
            // fall back to a placeholder rather than failing the whole load.
            location = (try? await locationT) ?? Location(
                id: locationId, name: "This location",
                address: "", managerId: userId,
                employees: [], tasks: [], lotteryForms: []
            )
            shifts = try await shiftsT
            forms = try await formsT
            payables = try await payablesT
            locEmployees = try await employeesT
            docs = try await docsT
            tasks = try await tasksT
        } catch {
            alerts = []
            return
        }

        var nameLookup: [String: String] = [:]
        for e in locEmployees { nameLookup[e.id] = e.name }

        var out: [ActionAlert] = []
        out.append(contentsOf: clockOutAlerts(shifts: shifts, location: location, names: nameLookup))
        out.append(contentsOf: missingRegisterAlerts(shifts: shifts, location: location, names: nameLookup))
        out.append(contentsOf: registerVarianceAlerts(shifts: shifts, location: location))
        out.append(contentsOf: lotteryNotClosedAlerts(forms: forms, location: location))
        out.append(contentsOf: lotteryVarianceAlerts(forms: forms, location: location))
        out.append(contentsOf: overduePayableAlerts(payables: payables, location: location))
        out.append(contentsOf: expiringDocAlerts(docs: docs, location: location))
        out.append(contentsOf: scheduleGapAlerts(employees: locEmployees))
        out.append(contentsOf: disapprovedTaskAlerts(tasks: tasks, location: location))

        out.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.sortKey < rhs.sortKey
        }
        alerts = out
    }

    // MARK: - Alert builders (mirror HomeAlertsViewModel)

    private func clockOutAlerts(shifts: [Shift], location: Location, names: [String: String]) -> [ActionAlert] {
        let cutoff = Date().addingTimeInterval(-unclosedShiftHours * 3600)
        return shifts.compactMap { shift in
            guard shift.isActive,
                  let clockIn = shift.clockInTime,
                  clockIn < cutoff else { return nil }
            let name = names[shift.employeeId] ?? "Employee"
            let hours = Int(Date().timeIntervalSince(clockIn) / 3600)
            return ActionAlert(
                id: "clockout_\(shift.id)",
                severity: .critical,
                title: "\(name) forgot to clock out",
                subtitle: "clocked in \(hours)h ago",
                route: .location(id: location.id),
                sortKey: 0,
                category: .forgotClockOut
            )
        }
    }

    private func missingRegisterAlerts(shifts: [Shift], location: Location, names: [String: String]) -> [ActionAlert] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -missingRegisterLookbackDays, to: Date()) ?? Date()
        return shifts.compactMap { shift in
            guard let clockOut = shift.clockOutTime, clockOut >= cutoff else { return nil }
            guard !shift.hasRegisterData else { return nil }
            if let h = shift.hoursWorked, h < 1 { return nil }
            let name = names[shift.employeeId] ?? "Employee"
            return ActionAlert(
                id: "noregister_\(shift.id)",
                severity: .critical,
                title: "Register data missing",
                subtitle: "\(name)'s shift · \(formatDate(clockOut))",
                route: .location(id: location.id),
                sortKey: 1,
                category: .missingRegister
            )
        }
    }

    private func registerVarianceAlerts(shifts: [Shift], location: Location) -> [ActionAlert] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -varianceLookbackDays, to: Date()) ?? Date()
        var out: [ActionAlert] = []
        for shift in shifts {
            guard let dateRef = shift.registerClosedAt ?? shift.clockOutTime,
                  dateRef >= cutoff else { continue }

            if !shift.registers.isEmpty {
                for register in shift.registers {
                    guard let v = register.overShort, abs(v) >= varianceThreshold else { continue }
                    out.append(makeVarianceAlert(
                        id: "regvar_\(shift.id)_\(register.id)",
                        location: location,
                        kind: "register",
                        value: v,
                        date: dateRef,
                        sortKey: 10
                    ))
                }
            } else if let v = shift.overShort, abs(v) >= varianceThreshold {
                out.append(makeVarianceAlert(
                    id: "regvar_legacy_\(shift.id)",
                    location: location,
                    kind: "register",
                    value: v,
                    date: dateRef,
                    sortKey: 10
                ))
            }
        }
        return out
    }

    private func lotteryNotClosedAlerts(forms: [LotteryForm], location: Location) -> [ActionAlert] {
        let calendar = Calendar.current
        let activityCutoff = calendar.date(byAdding: .day, value: -lotteryActivityWindowDays, to: Date()) ?? Date()
        let hasLottery = forms.contains { $0.submittedAt >= activityCutoff }
        guard hasLottery else { return [] }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let submittedYesterday = forms.contains { $0.submittedAt >= yesterday && $0.submittedAt < today }
        guard !submittedYesterday else { return [] }

        return [ActionAlert(
            id: "lotteryclose_\(location.id)",
            severity: .critical,
            title: "Lottery not closed",
            subtitle: "No submission for \(formatDate(yesterday))",
            route: .location(id: location.id),
            sortKey: 2,
            category: .lotteryNotClosed
        )]
    }

    private func lotteryVarianceAlerts(forms: [LotteryForm], location: Location) -> [ActionAlert] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -varianceLookbackDays, to: Date()) ?? Date()
        var out: [ActionAlert] = []
        for form in forms {
            guard form.submittedAt >= cutoff,
                  let v = form.shiftSummary?.overShort,
                  abs(v) >= varianceThreshold else { continue }
            out.append(makeVarianceAlert(
                id: "lotvar_\(form.id)",
                location: location,
                kind: "lottery",
                value: v,
                date: form.submittedAt,
                sortKey: 11
            ))
        }
        return out
    }

    private func overduePayableAlerts(payables: [Payable], location: Location) -> [ActionAlert] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let overdue = payables.filter { p in
            guard !p.isPaid, let due = p.dueDate else { return false }
            return Calendar.current.startOfDay(for: due) < todayStart
        }
        guard !overdue.isEmpty else { return [] }
        let total = overdue.reduce(0.0) { $0 + $1.amount }
        let s = overdue.count == 1 ? "" : "s"
        return [ActionAlert(
            id: "payables_\(location.id)",
            severity: .info,
            title: "\(overdue.count) payable\(s) overdue · \(formatCurrency(total))",
            subtitle: nil,
            route: .location(id: location.id),
            sortKey: 20,
            category: .overduePayables
        )]
    }

    private func expiringDocAlerts(docs: [Document], location: Location) -> [ActionAlert] {
        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: docExpiryWindowDays, to: now) ?? now

        return docs.compactMap { doc in
            // Filter to this location only — documents are stored
            // manager-wide, not under the location.
            guard doc.locationId == location.id else { return nil }
            guard let exp = doc.expiryDate, exp >= now, exp <= cutoff else { return nil }
            let days = max(0, calendar.dateComponents([.day], from: now, to: exp).day ?? 0)
            let severity: AlertSeverity = days <= 7 ? .warning : .info
            let s = days == 1 ? "" : "s"
            return ActionAlert(
                id: "doc_\(doc.id)",
                severity: severity,
                title: "\(doc.name) expires in \(days) day\(s)",
                subtitle: nil,
                route: .location(id: location.id),
                sortKey: 21,
                category: .expiringDocs
            )
        }
    }

    private func scheduleGapAlerts(employees: [Employee]) -> [ActionAlert] {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now

        return employees.compactMap { emp in
            guard let schedule = emp.weeklySchedule else { return nil }

            var workingDays = 0
            for i in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: i, to: weekStart),
                   schedule.worksOn(date: day) {
                    workingDays += 1
                }
            }
            guard workingDays == 0 else { return nil }

            return ActionAlert(
                id: "schedgap_\(emp.id)",
                severity: .info,
                title: "\(emp.name) has no shifts this week",
                subtitle: nil,
                route: .noAction,
                sortKey: 30,
                category: .scheduleGaps
            )
        }
    }

    private func disapprovedTaskAlerts(tasks: [WorkTask], location: Location) -> [ActionAlert] {
        // Filter manager-wide tasks to this location only.
        let here = tasks.filter { $0.locationId == location.id }
        let count = here.reduce(0) { partial, task in
            partial + (task.employeeCompletions.values.contains { $0.isDisapproved } ? 1 : 0)
        }
        guard count > 0 else { return [] }
        let s = count == 1 ? "" : "s"
        return [ActionAlert(
            id: "disapp_\(location.id)",
            severity: .warning,
            title: "\(count) task\(s) need rework",
            subtitle: nil,
            route: .location(id: location.id),
            sortKey: 12,
            category: .disapprovedTasks
        )]
    }

    // MARK: - Helpers

    private func makeVarianceAlert(
        id: String,
        location: Location,
        kind: String,
        value: Double,
        date: Date,
        sortKey: Int
    ) -> ActionAlert {
        let severity: AlertSeverity = abs(value) >= varianceCriticalThreshold ? .critical : .warning
        let label = value < 0 ? "SHORT" : "OVER"
        let dollars = formatCurrency(abs(value))
        let category: ManagerAlertCategory = (kind == "lottery") ? .lotteryVariance : .cashVariance
        return ActionAlert(
            id: id,
            severity: severity,
            title: "\(kind.capitalized) \(label) \(dollars)",
            subtitle: formatDate(date),
            route: .location(id: location.id),
            sortKey: sortKey,
            category: category
        )
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}
