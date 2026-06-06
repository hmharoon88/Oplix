//
//  DueThisWeekSheet.swift
//  Oplix
//
//  Drill-down sheet for the "This Week" card on the manager Home.
//  Shows every location that has receivables OR payables coming due
//  in the next 7 days, sorted by amount. Tapping a row opens that
//  location's Detail screen so the manager can collect / pay.
//

import SwiftUI

enum DueThisWeekKind: Identifiable {
    case receivables
    case payables
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .receivables: return "Receivables Due"
        case .payables:    return "Payables Due"
        }
    }
    var icon: String {
        switch self {
        case .receivables: return "arrow.down.circle.fill"
        case .payables:    return "arrow.up.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .receivables: return .green
        case .payables:    return .red
        }
    }
}

struct DueThisWeekSheet: View {
    let kind: DueThisWeekKind
    let pulse: WeeklyCashPulse
    let onSelectLocation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var rows: [WeeklyCashPulseLocation] {
        switch kind {
        case .receivables: return pulse.locationsWithReceivables
        case .payables:    return pulse.locationsWithPayables
        }
    }
    
    private var totalAmount: Double {
        switch kind {
        case .receivables: return pulse.receivablesDue
        case .payables:    return pulse.payablesDue
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient.ignoresSafeArea(edges: .top)
                
                VStack(spacing: 0) {
                    summaryHeader
                    
                    if rows.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(rows) { row in
                                    Button {
                                        // Hand control back to the parent so it
                                        // can swap out its presented modal —
                                        // dismissing here first avoids the
                                        // double-presentation glitch SwiftUI
                                        // gets when stacking covers.
                                        let id = row.id
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            onSelectLocation(id)
                                        }
                                    } label: {
                                        rowView(row)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 28))
                    .foregroundColor(kind.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 7 days")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                    Text(formatCurrency(totalAmount))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("Nothing due in the next 7 days")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Row
    
    private func rowView(_ row: WeeklyCashPulseLocation) -> some View {
        let amount: Double = {
            switch kind {
            case .receivables: return row.receivablesDue
            case .payables:    return row.payablesDue
            }
        }()
        let count: Int = {
            switch kind {
            case .receivables: return row.receivablesCount
            case .payables:    return row.payablesCount
            }
        }()
        
        return HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Theme.cloudBlue)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(formatCurrency(amount))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(kind.color)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }
}
