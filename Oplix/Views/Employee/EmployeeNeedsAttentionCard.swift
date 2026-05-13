//
//  EmployeeNeedsAttentionCard.swift
//  Oplix
//
//  A compact "Needs Attention" / "Today's Reminders" strip on the
//  employee + supervisor home screen. Surfaces personal items the user
//  should act on today: forgotten clock-outs, tasks needing rework,
//  pending tasks, register-data reminders, and "you're scheduled
//  today" nudges.
//
//  Pure derivation — every input comes from EmployeeHomeViewModel
//  which already fetches/observes the data, so this card costs zero
//  extra Firestore reads.
//

import SwiftUI

// MARK: - Alert model

enum EmployeeAlertSeverity: Int, Comparable {
    case critical = 0   // red — action required (forgot to clock out)
    case warning = 1    // orange — soft action (tasks rejected)
    case info = 2       // blue — informational nudge (scheduled today)
    
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    
    var tint: Color {
        switch self {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        }
    }
}

struct EmployeeAlert: Identifiable, Equatable {
    let id: String
    let severity: EmployeeAlertSeverity
    let icon: String
    let title: String
    let subtitle: String?
}

// MARK: - Derivation

enum EmployeeAlertBuilder {
    
    static func alerts(
        employeeId: String,
        employee: Employee?,
        currentShift: Shift?,
        allShifts: [Shift],
        myTasks: [WorkTask]
    ) -> [EmployeeAlert] {
        var out: [EmployeeAlert] = []
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        
        // 1) Forgot to clock out — any prior shift still flagged active.
        // We treat anything still active and clocked in > 12 hours ago as
        // "forgot": real shifts cap out well before that, so this is a
        // safe heuristic that won't fire mid-shift.
        for shift in allShifts where shift.employeeId == employeeId && shift.isActive {
            guard let clockIn = shift.clockInTime else { continue }
            let hours = now.timeIntervalSince(clockIn) / 3600.0
            if hours >= 12 {
                let hoursStr = String(format: "%.0f", hours)
                out.append(EmployeeAlert(
                    id: "forgot-clockout-\(shift.id)",
                    severity: .critical,
                    icon: "clock.badge.exclamationmark.fill",
                    title: "You're still clocked in",
                    subtitle: "Started \(hoursStr)h ago — open Clock In/Out to end the shift"
                ))
            }
        }
        
        // 2) Disapproved tasks — manager kicked one back. Highest-signal
        // alert other than a missed clock-out. Uses cycle-aware lookup so
        // a stale disapproval from a prior week doesn't haunt the user.
        let disapprovedCount = myTasks.reduce(0) { acc, task in
            let comp = task.getCompletion(for: employeeId)
            return acc + (comp?.isDisapproved == true ? 1 : 0)
        }
        if disapprovedCount > 0 {
            out.append(EmployeeAlert(
                id: "rework",
                severity: .warning,
                icon: "arrow.uturn.backward.circle.fill",
                title: "\(disapprovedCount) task\(disapprovedCount == 1 ? "" : "s") need redoing",
                subtitle: "Open Tasks to retake the photo or fix the issue"
            ))
        }
        
        // 3) Pending tasks for the current cycle — only show when the
        // count is non-trivial (> 0). Doesn't yell at the user when
        // they're already done for the day.
        // We count any of MY tasks that aren't fully completed OR are
        // disapproved (already covered) — we count "still owed" only.
        let pendingCount = myTasks.reduce(0) { acc, task in
            // isCompletedBy is cycle-aware AND already discounts disapprovals.
            return acc + (task.isCompletedBy(employeeId: employeeId) ? 0 : 1)
        } - disapprovedCount  // already surfaced separately
        if pendingCount > 0 {
            out.append(EmployeeAlert(
                id: "pending-tasks",
                severity: .info,
                icon: "checklist",
                title: "\(pendingCount) task\(pendingCount == 1 ? "" : "s") to do",
                subtitle: cycleSummary(for: myTasks)
            ))
        }
        
        // 4) Active shift, register data still empty. Reminds the user
        // that *closing* a shift requires a register entry. Only useful
        // for employees with the register permission.
        if let shift = currentShift,
           shift.isActive,
           shift.hasRegisterData == false,
           employee?.hasRegisterPermission == true {
            out.append(EmployeeAlert(
                id: "register-pending",
                severity: .info,
                icon: "cashregister.fill",
                title: "Enter register data before clocking out",
                subtitle: nil
            ))
        }
        
        // 5) Scheduled today, no shift created yet. Helpful nudge for
        // employees who forget to clock in at the start of the day.
        if let employee = employee,
           employee.worksOn(date: now),
           currentShift == nil {
            // Don't repeat if there's already a non-active shift for today
            // (means they finished early and clocked out — no nudge needed).
            let hasShiftToday = allShifts.contains { shift in
                shift.employeeId == employeeId &&
                (shift.clockInTime ?? Date.distantPast) >= todayStart &&
                (shift.clockInTime ?? Date.distantPast) < tomorrowStart
            }
            if !hasShiftToday {
                out.append(EmployeeAlert(
                    id: "scheduled-today",
                    severity: .info,
                    icon: "calendar.badge.clock",
                    title: "You're scheduled for today",
                    subtitle: "Tap Clock In/Out when you arrive"
                ))
            }
        }
        
        return out.sorted { $0.severity < $1.severity }
    }
    
    private static func cycleSummary(for tasks: [WorkTask]) -> String? {
        // Frequency mix: if mostly daily, say "for today"; if mostly
        // weekly/monthly, say "this week/month". Best-effort label.
        let counts = Dictionary(grouping: tasks, by: \.frequency).mapValues(\.count)
        let dominant = counts.max(by: { $0.value < $1.value })?.key
        switch dominant {
        case .daily:    return "Today"
        case .weekly:   return "This week"
        case .monthly:  return "This month"
        case .oneTime:  return "Open Tasks to begin"
        case .none:     return nil
        }
    }
}

// MARK: - Card

struct EmployeeNeedsAttentionCard: View {
    let alerts: [EmployeeAlert]
    let onTapTasks: (() -> Void)?
    let onTapClock: (() -> Void)?
    
    var body: some View {
        if alerts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NEEDS ATTENTION")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Spacer()
                }
                
                VStack(spacing: 0) {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { idx, alert in
                        Button {
                            handleTap(alert)
                        } label: {
                            row(for: alert)
                        }
                        .buttonStyle(.plain)
                        if idx < alerts.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .oplixCard()
            }
            .padding(.horizontal)
        }
    }
    
    private func row(for alert: EmployeeAlert) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(alert.severity.tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: alert.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(alert.severity.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                if let sub = alert.subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            // Show a chevron only if we know how to route the tap; for
            // FYI-only alerts (no callback wired) we leave it off so the
            // user doesn't poke at something that won't navigate.
            if hasRoute(for: alert) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    // MARK: - Routing
    
    private func hasRoute(for alert: EmployeeAlert) -> Bool {
        switch alert.id {
        case let id where id.hasPrefix("forgot-clockout-"): return onTapClock != nil
        case "rework", "pending-tasks":                     return onTapTasks != nil
        case "register-pending":                            return onTapClock != nil
        case "scheduled-today":                             return onTapClock != nil
        default:                                            return false
        }
    }
    
    private func handleTap(_ alert: EmployeeAlert) {
        switch alert.id {
        case let id where id.hasPrefix("forgot-clockout-"): onTapClock?()
        case "rework", "pending-tasks":                     onTapTasks?()
        case "register-pending":                            onTapClock?()
        case "scheduled-today":                             onTapClock?()
        default: break
        }
    }
}
