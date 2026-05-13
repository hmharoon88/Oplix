//
//  TodayCard.swift
//  Oplix
//
//  "Today at a glance" block on the manager Home screen.
//  Big revenue card + two compact metric tiles (clocked-in, tasks).
//

import SwiftUI

struct TodayCard: View {
    let snapshot: TodaySnapshot
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            revenueCard

            HStack(spacing: 12) {
                clockedInTile
                tasksTile
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Text("TODAY")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text("·")
                .foregroundColor(.secondary)
            Text(dateLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: Date())
    }

    // MARK: - Revenue (big card)

    private var revenueCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatCurrency(snapshot.revenue))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("Today's revenue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    trendChip
                }
            }
            Spacer()
            // Decorative right-side glyph keeps the card visually grounded
            // and gives a visual anchor for "money / today".
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 38))
                .foregroundColor(Theme.cloudBlue.opacity(0.18))
        }
        .padding()
        .oplixCard()
    }

    // Trend vs same weekday last week. Shown only when there's a non-zero
    // baseline — otherwise "▲ ∞%" or "—" looks broken.
    @ViewBuilder
    private var trendChip: some View {
        if let pct = snapshot.revenueChangePct {
            let isUp = pct >= 0
            let isFlat = abs(pct) < 0.5
            HStack(spacing: 2) {
                Image(systemName: isFlat ? "minus" : (isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"))
                    .font(.system(size: 9, weight: .bold))
                Text(String(format: "%.0f%% vs last \(weekdayShort)", abs(pct)))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isFlat ? .secondary : (isUp ? .green : .red))
        }
    }

    private var weekdayShort: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: Date())
    }

    // MARK: - Clocked-in tile

    private var clockedInTile: some View {
        metricTile(
            title: "CLOCKED IN",
            primary: "\(snapshot.clockedInCount) / \(max(snapshot.scheduledTodayCount, snapshot.clockedInCount))",
            secondary: clockedInSubtitle,
            progress: clockedInProgress,
            color: .blue
        )
    }

    private var clockedInSubtitle: String? {
        if snapshot.clockedInLocationNames.isEmpty {
            return snapshot.scheduledTodayCount > 0 ? "No one is on shift" : nil
        }
        if snapshot.clockedInLocationNames.count == 1 {
            return snapshot.clockedInLocationNames.first
        }
        // Compress to "Maple St, Pine Ave +1" so the tile doesn't overflow.
        if snapshot.clockedInLocationNames.count <= 2 {
            return snapshot.clockedInLocationNames.joined(separator: ", ")
        }
        let first = snapshot.clockedInLocationNames.prefix(2).joined(separator: ", ")
        let extra = snapshot.clockedInLocationNames.count - 2
        return "\(first) +\(extra)"
    }

    private var clockedInProgress: Double {
        let denom = max(snapshot.scheduledTodayCount, snapshot.clockedInCount)
        guard denom > 0 else { return 0 }
        return Double(snapshot.clockedInCount) / Double(denom)
    }

    // MARK: - Tasks tile

    private var tasksTile: some View {
        metricTile(
            title: "TASKS",
            primary: "\(snapshot.tasksCompleted) / \(snapshot.tasksTotal)",
            secondary: tasksSubtitle,
            progress: tasksProgress,
            color: .orange
        )
    }

    private var tasksSubtitle: String? {
        guard snapshot.tasksTotal > 0 else { return "No tasks today" }
        let pct = Int((tasksProgress * 100).rounded())
        return "\(pct)% done"
    }

    private var tasksProgress: Double {
        guard snapshot.tasksTotal > 0 else { return 0 }
        return Double(snapshot.tasksCompleted) / Double(snapshot.tasksTotal)
    }

    // MARK: - Tile builder

    private func metricTile(
        title: String,
        primary: String,
        secondary: String?,
        progress: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)

            Text(primary)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            // Compact progress bar — capped at 1 even if clockedIn somehow
            // exceeds the scheduled denominator (e.g. unscheduled walk-in).
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(color)

            if let secondary = secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .oplixCard()
    }

    // MARK: - Helpers

    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}
