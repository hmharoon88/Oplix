//
//  SupervisorTodayCard.swift
//  Oplix
//
//  "Today at this location" card shown only when the logged-in user is
//  a supervisor. Gives the supervisor a quick read on their location's
//  pulse without forcing them to drill into Tasks / Shifts / Lottery
//  individually.
//
//  Pure derivation from data EmployeeHomeViewModel already loads:
//  `allShifts`, `allTasks`, `allEmployees`, `location`. Zero extra
//  Firestore reads.
//

import SwiftUI

// MARK: - Snapshot

struct SupervisorTodaySnapshot {
    var revenue: Double = 0
    var clockedInCount: Int = 0
    var clockedInNames: [String] = []
    var tasksCompleted: Int = 0
    var tasksTotal: Int = 0
    var hasCashVariance: Bool = false   // any shift today closed over/short
    var varianceTotal: Double = 0       // signed sum of |overShort| today
    
    var taskPct: Double {
        guard tasksTotal > 0 else { return 0 }
        return Double(tasksCompleted) / Double(tasksTotal)
    }
    
    var isEmpty: Bool {
        revenue == 0 && clockedInCount == 0 && tasksTotal == 0 && !hasCashVariance
    }
}

// MARK: - Builder

enum SupervisorTodaySnapshotBuilder {
    
    static func build(
        allShifts: [Shift],
        allTasks: [WorkTask],
        allEmployees: [Employee]
    ) -> SupervisorTodaySnapshot {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        
        var snap = SupervisorTodaySnapshot()
        let nameById = Dictionary(uniqueKeysWithValues: allEmployees.map { ($0.id, $0.name) })
        
        // Revenue + variance from today's shifts
        for shift in allShifts {
            // Active "currently clocked in" — independent of date.
            if shift.isActive {
                snap.clockedInCount += 1
                if let name = nameById[shift.employeeId] { snap.clockedInNames.append(name) }
            }
            
            // Anything attributable to "today" needs a date anchor. We use
            // the register-closed-at when present (most accurate), else
            // the clock-out time, else the clock-in time.
            let dateAnchor = shift.registerClosedAt ?? shift.clockOutTime ?? shift.clockInTime
            guard let date = dateAnchor,
                  date >= todayStart, date < tomorrowStart else { continue }
            
            // Revenue from this shift
            if !shift.registers.isEmpty {
                for r in shift.registers {
                    snap.revenue += (r.cashSale ?? 0) + (r.creditCard ?? 0)
                }
            } else {
                snap.revenue += (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
            }
            
            // Variance — only counted once we actually have register data
            // (otherwise overShort is meaningless).
            if shift.hasRegisterData, let overShort = shift.overShort, abs(overShort) >= 1 {
                snap.hasCashVariance = true
                snap.varianceTotal += overShort
            }
        }
        
        // Tasks today — count fully-completed (location-wide) vs assigned.
        for task in allTasks {
            snap.tasksTotal += 1
            if task.currentCycleCompletions.values.contains(where: { $0.countsAsCompleted }) {
                snap.tasksCompleted += 1
            }
        }
        
        return snap
    }
}

// MARK: - Card

struct SupervisorTodayCard: View {
    let snapshot: SupervisorTodaySnapshot
    let locationName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY AT THIS LOCATION")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                Text(locationName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            VStack(spacing: 12) {
                // Revenue (big number, full-width). Mirrors the shape of
                // the manager TodayCard's revenue tile so users moving
                // between roles get the same mental model.
                revenueRow
                
                HStack(spacing: 12) {
                    metricTile(
                        label: "CLOCKED IN",
                        primary: "\(snapshot.clockedInCount)",
                        secondary: clockedInLabel,
                        color: .green
                    )
                    metricTile(
                        label: "TASKS",
                        primary: snapshot.tasksTotal > 0
                            ? "\(Int(snapshot.taskPct * 100))%"
                            : "—",
                        secondary: snapshot.tasksTotal > 0
                            ? "\(snapshot.tasksCompleted)/\(snapshot.tasksTotal) done"
                            : "no tasks today",
                        color: .orange
                    )
                }
                
                if snapshot.hasCashVariance {
                    varianceRow
                }
            }
            .padding(14)
            .oplixCard()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Pieces
    
    private var revenueRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's revenue")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatCurrency(snapshot.revenue))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
            }
            Spacer()
        }
    }
    
    private var clockedInLabel: String {
        if snapshot.clockedInCount == 0 { return "no one on shift" }
        // Show the first 2 names then "+N" so we don't blow up the tile.
        let first = snapshot.clockedInNames.prefix(2).joined(separator: ", ")
        let extra = snapshot.clockedInNames.count - 2
        if extra > 0 { return "\(first) +\(extra)" }
        return first
    }
    
    private var varianceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
            let amount = formatCurrency(abs(snapshot.varianceTotal))
            let kind = snapshot.varianceTotal >= 0 ? "over" : "short"
            Text("Register \(kind) by \(amount) today")
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(.top, 4)
    }
    
    private func metricTile(label: String, primary: String, secondary: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(primary)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(secondary)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}
