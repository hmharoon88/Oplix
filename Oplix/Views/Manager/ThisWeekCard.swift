//
//  ThisWeekCard.swift
//  Oplix
//
//  "This Week" cash pulse card on the manager Home screen. Shows the
//  total $ of receivables coming due in the next 7 days, payables coming
//  due in the next 7 days, and a net (receivables − payables).
//

import SwiftUI

struct ThisWeekCard: View {
    let pulse: WeeklyCashPulse
    let onTapReceivables: () -> Void
    let onTapPayables: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader

            VStack(spacing: 0) {
                Button(action: onTapReceivables) {
                    pulseRow(
                        icon: "arrow.down.circle.fill",
                        iconColor: .green,
                        label: "Receivables due",
                        count: pulse.receivablesCount,
                        amount: pulse.receivablesDue,
                        amountColor: .green
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                Button(action: onTapPayables) {
                    pulseRow(
                        icon: "arrow.up.circle.fill",
                        iconColor: .red,
                        label: "Payables due",
                        count: pulse.payablesCount,
                        amount: pulse.payablesDue,
                        amountColor: .red
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                netRow
            }
            .oplixCard()
        }
        .padding(.horizontal)
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Text("THIS WEEK")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Spacer()
        }
    }

    // MARK: - Rows

    private func pulseRow(
        icon: String,
        iconColor: Color,
        label: String,
        count: Int,
        amount: Double,
        amountColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                if count > 0 {
                    Text("\(count) item\(count == 1 ? "" : "s") · next 7 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Nothing due in the next 7 days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(formatCurrency(amount))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(count > 0 ? amountColor : .secondary)

            // Chevron only when there's actually something tappable to drill into.
            // (Tapping when count is 0 still works — we just don't advertise it.)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(count > 0 ? 1 : 0.4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var netRow: some View {
        HStack(spacing: 12) {
            // Spacer matches the icon column above so labels line up.
            Color.clear.frame(width: 40, height: 1)

            Text("Net")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.black)

            Spacer()

            // Sign-aware formatting: "+$5,200" for positive, "-$3,200" for negative.
            // Color also flips so the read is instant.
            Text(formatNet(pulse.net))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(pulse.net >= 0 ? .green : .red)

            // Invisible chevron-width spacer to align the value column
            // with the rows above (which have a chevron at the end).
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.clear)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    private func formatNet(_ amount: Double) -> String {
        let abs = formatCurrency(abs(amount))
        let prefix = amount >= 0 ? "+" : "-"
        return "\(prefix)\(abs)"
    }
}
