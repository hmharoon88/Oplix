//
//  HomeAlertsViewModel.swift
//  Oplix
//
//  Aggregates "Needs Attention" alerts for the manager Home screen.
//  Pulls from shifts, lottery forms, payables, documents, employee schedules,
//  and task completions across every location the manager owns.
//

import Foundation
import SwiftUI

// MARK: - Severity

enum AlertSeverity: Int, Comparable {
    case critical = 0  // red — operational, books are wrong
    case warning = 1   // orange — needs attention soon
    case info = 2      // yellow — fyi / admin items

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var tint: Color {
        switch self {
        case .critical: return Color.red
        case .warning:  return Color.orange
        case .info:     return Color(red: 0.85, green: 0.7, blue: 0.0)
        }
    }
}

// MARK: - Route

// What tapping an alert row should do. For now most alerts open the
// owning location's detail screen — the manager finishes the fix
// from there. Phase 4 polish can add deep-linking into specific sections.
enum AlertRoute: Equatable {
    case location(id: String)
    case noAction
}

// MARK: - Categories

/// User-facing alert categories shown in the manager Home customization
/// sheet. The user can hide entire categories from "Needs Attention"
/// without losing the underlying data anywhere else in the app.
///
/// Each category maps 1:1 to one alert builder in `HomeAlertsViewModel`.
/// Adding a new alert type?
///   1. Add a case here.
///   2. Tag the new alerts with that category.
///   3. The customization screen picks it up automatically (CaseIterable).
enum ManagerAlertCategory: String, CaseIterable, Identifiable, Codable {
    case forgotClockOut
    case missingRegister
    case cashVariance
    case lotteryNotClosed
    case lotteryVariance
    case disapprovedTasks
    case overduePayables
    case expiringDocs
    case scheduleGaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forgotClockOut:   return "Forgot to clock out"
        case .missingRegister:  return "Register data missing"
        case .cashVariance:     return "Cash over / short"
        case .lotteryNotClosed: return "Lottery not closed"
        case .lotteryVariance:  return "Lottery over / short"
        case .disapprovedTasks: return "Tasks need rework"
        case .overduePayables:  return "Overdue payables"
        case .expiringDocs:     return "Expiring documents"
        case .scheduleGaps:     return "Schedule gaps"
        }
    }

    var subtitle: String {
        switch self {
        case .forgotClockOut:   return "Active shifts older than 12 hours"
        case .missingRegister:  return "Closed shifts with no register data (last 7 days)"
        case .cashVariance:     return "Register over/short ≥ $5 in last 7 days"
        case .lotteryNotClosed: return "Lottery active but no submission yesterday"
        case .lotteryVariance:  return "Lottery shift over/short ≥ $5 in last 7 days"
        case .disapprovedTasks: return "Tasks the manager kicked back to redo"
        case .overduePayables:  return "Unpaid payables past due date"
        case .expiringDocs:     return "Documents expiring within 30 days"
        case .scheduleGaps:     return "Employees with no shifts this week"
        }
    }

    var icon: String {
        switch self {
        case .forgotClockOut:   return "clock.badge.exclamationmark.fill"
        case .missingRegister:  return "tray.fill"
        case .cashVariance:     return "dollarsign.circle.fill"
        case .lotteryNotClosed: return "ticket"
        case .lotteryVariance:  return "ticket.fill"
        case .disapprovedTasks: return "arrow.uturn.backward.circle.fill"
        case .overduePayables:  return "creditcard.trianglebadge.exclamationmark"
        case .expiringDocs:     return "doc.text.fill"
        case .scheduleGaps:     return "calendar.badge.exclamationmark"
        }
    }
}

// MARK: - Alert

struct ActionAlert: Identifiable, Equatable {
    let id: String
    let severity: AlertSeverity
    let title: String
    let subtitle: String?
    let route: AlertRoute
    // Sort priority inside the same severity bucket. Lower = higher in list.
    let sortKey: Int
    // Category drives the per-category visibility toggle on the manager
    // Home customization screen.
    let category: ManagerAlertCategory
}

extension Array where Element == ActionAlert {
    /// Hides alerts the manager has acknowledged on Home or Location screens.
    func filteringAcknowledged(_ acknowledgedIds: Set<String>) -> [ActionAlert] {
        filter { !acknowledgedIds.contains($0.id) }
    }
}

// MARK: - This-week pulse

// Per-location row used by the DueThisWeekSheet. We carry a snapshot of
// the location (name + id) plus the totals so the sheet renders in one
// pass without re-fetching anything.
struct WeeklyCashPulseLocation: Identifiable, Equatable {
    let id: String           // location id
    let name: String
    var receivablesDue: Double
    var receivablesCount: Int
    var payablesDue: Double
    var payablesCount: Int
}

// Receivables/payables coming due in the next 7 days (today through +7).
// Surfaced as the "This Week" card on the manager Home — gives a quick
// cash-flow read without diving into individual location books.
struct WeeklyCashPulse: Equatable {
    var receivablesDue: Double = 0
    var receivablesCount: Int = 0
    var payablesDue: Double = 0
    var payablesCount: Int = 0
    // Per-location breakdown so the "This Week" card taps can drill into
    // a list of locations and the user can pick which one to fix first.
    var perLocation: [WeeklyCashPulseLocation] = []
    
    var net: Double { receivablesDue - payablesDue }
    
    // Filtered helpers for the drill-down sheet.
    var locationsWithReceivables: [WeeklyCashPulseLocation] {
        perLocation
            .filter { $0.receivablesCount > 0 }
            .sorted { $0.receivablesDue > $1.receivablesDue }
    }
    var locationsWithPayables: [WeeklyCashPulseLocation] {
        perLocation
            .filter { $0.payablesCount > 0 }
            .sorted { $0.payablesDue > $1.payablesDue }
    }
}

// MARK: - Today's lottery roll-up

// One row per location, summarizing the lottery activity for *today*
// (forms submitted between today's startOfDay and tomorrow's startOfDay).
// Aggregates across all terminals at that location into a single
// over/short total — supervisors can drill into LocationDetail for
// the per-terminal breakdown.
struct LotteryTodayRow: Identifiable, Equatable {
    let id: String              // location id
    let name: String            // location name
    var formsCount: Int         // # of forms submitted today (across terminals)
    var cashEnclosed: Double    // sum of reported/shift-end cash enclosed today
    var overShort: Double       // signed sum of overShort across today's forms
    var hadOverShortData: Bool  // false = no terminal reported a number; treat as "—"
    
    enum Status { case over, short, even, noData }
    
    var status: Status {
        guard hadOverShortData else { return .noData }
        if abs(overShort) < 0.005 { return .even }
        return overShort > 0 ? .over : .short
    }
}

// MARK: - View Model

@MainActor
final class HomeAlertsViewModel: ObservableObject {
    @Published private(set) var alerts: [ActionAlert] = []
    @Published private(set) var weeklyPulse: WeeklyCashPulse = WeeklyCashPulse()
    @Published private(set) var lotteryToday: [LotteryTodayRow] = []
    @Published private(set) var isLoading = false

    private let userId: String
    private let firebaseService = FirebaseService.shared

    // Don't flag pennies-level register / lottery variances — that's just
    // counting noise. $5 is the standard retail tolerance.
    private let varianceThreshold: Double = 5.0
    // Critical-vs-warning split for cash variance.
    private let varianceCriticalThreshold: Double = 20.0
    // Active shifts older than this without a clock-out are flagged.
    private let unclosedShiftHours: Double = 12.0
    // Window for cash-variance scanning. Older shifts are history, not action.
    private let varianceLookbackDays: Int = 7
    // Window for "register data missing" scanning.
    private let missingRegisterLookbackDays: Int = 7
    // Window used to decide whether a location "uses lottery" (any submission
    // within this window means lottery is active there).
    private let lotteryActivityWindowDays: Int = 30
    // Documents expiring inside this window get surfaced.
    private let docExpiryWindowDays: Int = 30

    init(userId: String) {
        self.userId = userId
    }

    func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }

        // Fan out top-level fetches in parallel.
        async let locationsTask = firebaseService.fetchLocations(userId: userId)
        async let employeesTask = firebaseService.fetchManagerEmployees(userId: userId)
        async let tasksTask = firebaseService.fetchManagerTasks(userId: userId)
        async let docsTask = firebaseService.fetchAllDocuments(userId: userId)

        let locations: [Location]
        let employees: [Employee]
        let tasks: [WorkTask]
        let docs: [Document]
        do {
            locations = try await locationsTask
            employees = try await employeesTask
            tasks = try await tasksTask
            docs = try await docsTask
        } catch {
            // If the top-level fetches fail we have nothing to render anyway.
            alerts = []
            return
        }

        // Build a single employee-name lookup (master employees + each
        // location's employees) so per-shift alerts can resolve names.
        var nameLookup: [String: String] = [:]
        for e in employees { nameLookup[e.id] = e.name }

        // Per-location alerts + weekly pulse contribution — fan out so we
        // don't serialize Firestore calls. Each task returns its alerts,
        // its employee-name contributions, and its slice of the pulse.
        var perLocationAlerts: [ActionAlert] = []
        var pulse = WeeklyCashPulse()
        var lotteryRows: [LotteryTodayRow] = []
        await withTaskGroup(
            of: ([ActionAlert], [String: String], WeeklyCashPulseLocation, LotteryTodayRow).self
        ) { group in
            for location in locations {
                group.addTask { [self] in
                    await alertsForLocation(location)
                }
            }
            for await (locAlerts, locEmployeeNames, locPulse, locLottery) in group {
                perLocationAlerts.append(contentsOf: locAlerts)
                for (id, name) in locEmployeeNames where nameLookup[id] == nil {
                    nameLookup[id] = name
                }
                pulse.receivablesDue += locPulse.receivablesDue
                pulse.receivablesCount += locPulse.receivablesCount
                pulse.payablesDue += locPulse.payablesDue
                pulse.payablesCount += locPulse.payablesCount
                // Only keep locations that contributed something — keeps the
                // drill-down sheet short and tidy.
                if locPulse.receivablesCount > 0 || locPulse.payablesCount > 0 {
                    pulse.perLocation.append(locPulse)
                }
                // Always include the location in the lottery roll-up so
                // the user can see "no submissions yet" for any location
                // they expect activity from. The card itself can decide
                // how to render rows with formsCount == 0.
                lotteryRows.append(locLottery)
            }
        }
        weeklyPulse = pulse
        // Stable order: locations with the largest absolute over/short
        // first (those need attention), then locations with no data
        // last. Same-bucket rows fall back to alphabetical.
        lotteryToday = lotteryRows.sorted { a, b in
            switch (a.hadOverShortData, b.hadOverShortData) {
            case (true, false): return true
            case (false, true): return false
            default:
                if a.hadOverShortData {
                    let absDiff = abs(a.overShort) - abs(b.overShort)
                    if absDiff != 0 { return absDiff > 0 }
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        // Patch in employee names that were only available at the location level.
        // (Per-location task above already resolved them when building rows; this
        // is just defensive in case future builders also want them.)
        _ = nameLookup

        var collected = perLocationAlerts
        collected.append(contentsOf: expiringDocAlerts(docs: docs, locations: locations))
        collected.append(contentsOf: scheduleGapAlerts(employees: employees))
        collected.append(contentsOf: disapprovedTaskAlerts(tasks: tasks, locations: locations))

        // Sort: severity first (critical > warning > info), then stable sortKey.
        collected.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return lhs.sortKey < rhs.sortKey
        }

        alerts = collected
    }

    // MARK: - Per-location pipeline

    // Returns (alerts, employeeNamesById, weeklyPulseSlice). The caller
    // merges name contributions into a global lookup and sums the pulse
    // slices across locations to render the This Week card.
    private func alertsForLocation(
        _ location: Location
    ) async -> ([ActionAlert], [String: String], WeeklyCashPulseLocation, LotteryTodayRow) {
        var nameLookup: [String: String] = [:]
        let emptyPulse = WeeklyCashPulseLocation(
            id: location.id, name: location.name,
            receivablesDue: 0, receivablesCount: 0,
            payablesDue: 0, payablesCount: 0
        )
        let emptyLottery = LotteryTodayRow(
            id: location.id, name: location.name,
            formsCount: 0, cashEnclosed: 0,
            overShort: 0, hadOverShortData: false
        )

        async let shiftsT = firebaseService.fetchShifts(userId: userId, locationId: location.id)
        async let formsT = firebaseService.fetchLotteryForms(userId: userId, locationId: location.id)
        async let payablesT = firebaseService.fetchPayables(userId: userId, locationId: location.id)
        async let receivablesT = firebaseService.fetchReceivables(userId: userId, locationId: location.id)
        async let locEmployeesT = firebaseService.fetchEmployees(userId: userId, locationId: location.id)

        let shifts: [Shift]
        let forms: [LotteryForm]
        let payables: [Payable]
        let receivables: [Receivable]
        let locEmployees: [Employee]
        do {
            shifts = try await shiftsT
            forms = try await formsT
            payables = try await payablesT
            receivables = try await receivablesT
            locEmployees = try await locEmployeesT
        } catch {
            return ([], nameLookup, emptyPulse, emptyLottery)
        }

        for e in locEmployees { nameLookup[e.id] = e.name }

        var out: [ActionAlert] = []
        out.append(contentsOf: clockOutAlerts(shifts: shifts, location: location, names: nameLookup))
        out.append(contentsOf: missingRegisterAlerts(shifts: shifts, location: location, names: nameLookup))
        out.append(contentsOf: registerVarianceAlerts(shifts: shifts, location: location))
        out.append(contentsOf: lotteryNotClosedAlerts(forms: forms, location: location))
        out.append(contentsOf: lotteryVarianceAlerts(forms: forms, location: location))
        out.append(contentsOf: overduePayableAlerts(payables: payables, location: location))
        
        let pulse = computePulse(
            location: location,
            payables: payables,
            receivables: receivables
        )
        let lottery = computeLotteryToday(location: location, forms: forms)
        return (out, nameLookup, pulse, lottery)
    }
    
    // MARK: - Today's lottery roll-up
    
    // Aggregates today's submitted lottery forms across every terminal
    // at the location into one row. `hadOverShortData` distinguishes
    // "no terminal reported a number" (render as "—") from "all
    // terminals exactly broke even" (render as $0.00 / Even).
    private func computeLotteryToday(
        location: Location,
        forms: [LotteryForm]
    ) -> LotteryTodayRow {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        
        var row = LotteryTodayRow(
            id: location.id, name: location.name,
            formsCount: 0, cashEnclosed: 0,
            overShort: 0, hadOverShortData: false
        )
        for form in forms {
            guard form.submittedAt >= todayStart, form.submittedAt < tomorrowStart else { continue }
            row.formsCount += 1
            if let summary = form.shiftSummary {
                row.cashEnclosed += Self.cashEnclosedAmount(from: summary)
                if let overShort = summary.overShort {
                    row.overShort += overShort
                    row.hadOverShortData = true
                }
            }
        }
        return row
    }

    /// Cash the employee counted and enclosed for the shift. Requires
    /// over/short (saved at close since cash in hand is mandatory).
    private static func cashEnclosedAmount(from summary: ShiftSummaryData) -> Double {
        summary.cashInBagNet + (summary.overShort ?? 0)
    }
    
    // MARK: - Weekly cash pulse
    
    // Items "due this week" = unpaid/unreceived with dueDate inside the
    // window [today, today + 7 days]. Window matches the user's stated
    // intent: "Receivables due this week / Payables due this week".
    private func computePulse(
        location: Location,
        payables: [Payable],
        receivables: [Receivable]
    ) -> WeeklyCashPulseLocation {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? todayStart
        
        var p = WeeklyCashPulseLocation(
            id: location.id, name: location.name,
            receivablesDue: 0, receivablesCount: 0,
            payablesDue: 0, payablesCount: 0
        )
        for payable in payables {
            guard !payable.isPaid, let due = payable.dueDate else { continue }
            // Include overdue items too — they're definitionally "due now",
            // even more so than items due Friday.
            guard due < windowEnd else { continue }
            p.payablesDue += payable.amount
            p.payablesCount += 1
        }
        for receivable in receivables {
            guard !receivable.isReceived, let due = receivable.dueDate else { continue }
            guard due < windowEnd else { continue }
            p.receivablesDue += receivable.amount
            p.receivablesCount += 1
        }
        return p
    }

    // MARK: - Individual alert builders

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
                subtitle: "\(location.name) · clocked in \(hours)h ago",
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
            // Filter out test/mistake shifts that only lasted a few minutes.
            if let h = shift.hoursWorked, h < 1 { return nil }
            let name = names[shift.employeeId] ?? "Employee"
            return ActionAlert(
                id: "noregister_\(shift.id)",
                severity: .critical,
                title: "\(location.name) — register data missing",
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

            // New-format multi-register
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
                // Legacy single-register shape (pre multi-register refactor).
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
        // Heuristic: a location "uses lottery" when at least one form has been
        // submitted in the recent activity window. Avoids false positives on
        // locations that never had lottery configured.
        let calendar = Calendar.current
        let activityCutoff = calendar.date(byAdding: .day, value: -lotteryActivityWindowDays, to: Date()) ?? Date()
        let hasLottery = forms.contains { $0.submittedAt >= activityCutoff }
        guard hasLottery else { return [] }

        // Was anything submitted yesterday (entire calendar day)?
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let submittedYesterday = forms.contains { $0.submittedAt >= yesterday && $0.submittedAt < today }
        guard !submittedYesterday else { return [] }

        return [ActionAlert(
            id: "lotteryclose_\(location.id)",
            severity: .critical,
            title: "\(location.name) — lottery not closed",
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
            subtitle: location.name,
            route: .location(id: location.id),
            sortKey: 20,
            category: .overduePayables
        )]
    }

    private func expiringDocAlerts(docs: [Document], locations: [Location]) -> [ActionAlert] {
        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: docExpiryWindowDays, to: now) ?? now
        let nameById = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) })

        return docs.compactMap { doc in
            guard let exp = doc.expiryDate, exp >= now, exp <= cutoff else { return nil }
            let days = max(0, calendar.dateComponents([.day], from: now, to: exp).day ?? 0)
            let severity: AlertSeverity = days <= 7 ? .warning : .info
            let locName = nameById[doc.locationId] ?? "Location"
            let s = days == 1 ? "" : "s"
            return ActionAlert(
                id: "doc_\(doc.id)",
                severity: severity,
                title: "\(doc.name) expires in \(days) day\(s)",
                subtitle: locName,
                route: .location(id: doc.locationId),
                sortKey: 21,
                category: .expiringDocs
            )
        }
    }

    private func scheduleGapAlerts(employees: [Employee]) -> [ActionAlert] {
        let calendar = Calendar.current
        let now = Date()
        // Start of current week, using the user's locale.
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? now

        return employees.compactMap { emp in
            // Employees with no schedule defined at all aren't necessarily a
            // problem (they might be on-call) — skip rather than spam.
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

    private func disapprovedTaskAlerts(tasks: [WorkTask], locations: [Location]) -> [ActionAlert] {
        var byLocation: [String: Int] = [:]
        for task in tasks {
            // locationId is optional — manager-level tasks that haven't been
            // assigned to a location yet have nil. Those can't drive a
            // location-scoped alert, so skip them here.
            guard let locationId = task.locationId else { continue }
            let hasDisapproved = task.employeeCompletions.values.contains { $0.isDisapproved }
            if hasDisapproved { byLocation[locationId, default: 0] += 1 }
        }
        guard !byLocation.isEmpty else { return [] }
        let nameById = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0.name) })
        return byLocation.map { locId, count in
            let s = count == 1 ? "" : "s"
            return ActionAlert(
                id: "disapp_\(locId)",
                severity: .warning,
                title: "\(count) task\(s) need rework",
                subtitle: nameById[locId] ?? "Location",
                route: .location(id: locId),
                sortKey: 12,
                category: .disapprovedTasks
            )
        }
    }

    // MARK: - Helpers

    // Builds a register / lottery variance alert with consistent wording.
    // Severity flips to .critical above the critical threshold.
    private func makeVarianceAlert(
        id: String,
        location: Location,
        kind: String,           // "register" or "lottery"
        value: Double,
        date: Date,
        sortKey: Int
    ) -> ActionAlert {
        let severity: AlertSeverity = abs(value) >= varianceCriticalThreshold ? .critical : .warning
        let label = value < 0 ? "SHORT" : "OVER"
        let dollars = formatCurrency(abs(value))
        // Map the kind string to its category. Any new variance kinds
        // would need a category added here AND in `ManagerAlertCategory`.
        let category: ManagerAlertCategory = (kind == "lottery") ? .lotteryVariance : .cashVariance
        return ActionAlert(
            id: id,
            severity: severity,
            title: "\(location.name) \(kind) \(label) \(dollars)",
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
