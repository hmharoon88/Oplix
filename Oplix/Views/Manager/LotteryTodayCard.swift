//
//  LotteryTodayCard.swift
//  Oplix
//
//  Manager Home section: today's lottery activity for every location,
//  with an over/short pill per row. Powered by HomeAlertsViewModel
//  which already fetches lottery forms per location for the lottery
//  alerts — so this card costs zero extra Firestore reads.
//

import SwiftUI

struct LotteryTodayCard: View {
    let rows: [LotteryTodayRow]
    let onTapLocation: (String) -> Void
    
    // We separate "had activity today" from "no submissions yet" because
    // showing a long list of "—" rows for every location dilutes the
    // signal. Active locations come first, idle locations are tucked
    // into a collapsed footer.
    @State private var showInactive: Bool = false
    
    private var activeRows: [LotteryTodayRow] {
        rows.filter { $0.formsCount > 0 }
    }
    private var inactiveRows: [LotteryTodayRow] {
        rows.filter { $0.formsCount == 0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            
            VStack(spacing: 0) {
                if activeRows.isEmpty && inactiveRows.isEmpty {
                    emptyRow
                } else {
                    if activeRows.isEmpty {
                        idleSummaryRow
                    } else {
                        ForEach(Array(activeRows.enumerated()), id: \.element.id) { idx, row in
                            Button { onTapLocation(row.id) } label: { rowView(row) }
                                .buttonStyle(.plain)
                            if idx < activeRows.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    
                    if !inactiveRows.isEmpty && !activeRows.isEmpty {
                        Divider().padding(.leading, 16)
                        inactiveToggleRow
                        if showInactive {
                            ForEach(Array(inactiveRows.enumerated()), id: \.element.id) { idx, row in
                                Button { onTapLocation(row.id) } label: { rowView(row) }
                                    .buttonStyle(.plain)
                                if idx < inactiveRows.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
                
                // Net total footer — only meaningful when ≥ 2 active
                // locations contributed (single-location accounts get the
                // same number twice, which is noise).
                if activeRows.count >= 2 {
                    Divider().padding(.leading, 16)
                    netRow
                }
            }
            .oplixCard()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("LOTTERY TODAY")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Spacer()
            // Mini date label so a screenshot is always self-explanatory.
            Text(todayLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date())
    }
    
    // MARK: - Rows
    
    private var emptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            Text("No locations to show")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(14)
    }
    
    // Compact row used when EVERY location is idle today. Saves the
    // user from skimming a wall of "—" rows.
    private var idleSummaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No lottery shifts closed yet today")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text("\(inactiveRows.count) location\(inactiveRows.count == 1 ? "" : "s") with no submissions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
    
    private func rowView(_ row: LotteryTodayRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text(secondaryLabel(for: row))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusPill(for: row)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private func secondaryLabel(for row: LotteryTodayRow) -> String {
        if row.formsCount == 0 { return "no submissions" }
        let formsBit = "\(row.formsCount) shift\(row.formsCount == 1 ? "" : "s")"
        if row.totalSold > 0 {
            return "\(formsBit) · \(formatCurrency(row.totalSold)) sold"
        }
        return formsBit
    }
    
    @ViewBuilder
    private func statusPill(for row: LotteryTodayRow) -> some View {
        switch row.status {
        case .over:
            pill(text: "+\(formatCurrency(row.overShort))", color: .green, system: "arrow.up")
        case .short:
            pill(text: "-\(formatCurrency(abs(row.overShort)))", color: .red, system: "arrow.down")
        case .even:
            pill(text: "Even", color: .blue, system: "equal")
        case .noData:
            pill(text: "—", color: .gray, system: nil)
        }
    }
    
    private func pill(text: String, color: Color, system: String?) -> some View {
        HStack(spacing: 4) {
            if let system = system {
                Image(systemName: system)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    // MARK: - Inactive toggle
    
    private var inactiveToggleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                showInactive.toggle()
            }
        } label: {
            HStack {
                Image(systemName: showInactive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(showInactive
                     ? "Hide \(inactiveRows.count) idle location\(inactiveRows.count == 1 ? "" : "s")"
                     : "Show \(inactiveRows.count) idle location\(inactiveRows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            .foregroundColor(Theme.cloudBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Net
    
    private var netRow: some View {
        let withData = activeRows.filter { $0.hadOverShortData }
        let total = withData.reduce(0) { $0 + $1.overShort }
        let color: Color = abs(total) < 0.005 ? .blue : (total > 0 ? .green : .red)
        let label: String = abs(total) < 0.005
            ? "Even across \(withData.count) location\(withData.count == 1 ? "" : "s")"
            : (total > 0 ? "Net over" : "Net short")
        return HStack {
            Text("Net")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.black)
            Spacer()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(total >= 0
                 ? "+\(formatCurrency(abs(total)))"
                 : "-\(formatCurrency(abs(total)))")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        // For the over/short pills, cents matter — a $0.42 short still
        // belongs in red, not glossed over as zero.
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
