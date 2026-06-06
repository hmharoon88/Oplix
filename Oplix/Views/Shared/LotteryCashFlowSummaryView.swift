//
//  LotteryCashFlowSummaryView.swift
//  Oplix
//
//  Cash in / cash out table for lottery shift summaries. Uses existing
//  `ShiftSummaryData` fields only — no formula changes.
//

import SwiftUI

struct LotteryCashFlowSummaryView: View {
    let summary: ShiftSummaryData
    /// While the employee is typing at close, show live actual + variance.
    var projectedActualEnclosed: Double? = nil

    private var resolvedActualEnclosed: Double? {
        projectedActualEnclosed ?? summary.actualEnclosedCash
    }

    private var resolvedVariance: Double? {
        if let projected = projectedActualEnclosed {
            return projected - summary.cashInBagNet
        }
        return summary.overShort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LotterySummaryDisplayName.cashFlowTitle)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)

            flowBlock(
                title: "Cash in",
                lines: [
                    (LotterySummaryDisplayName.instantSales, summary.instantTotal),
                    (LotterySummaryDisplayName.onlineSales, summary.onlineTotal),
                    (LotterySummaryDisplayName.registerStartingCash, summary.registerCash)
                ],
                totalLabel: LotterySummaryDisplayName.totalCashIn,
                totalValue: summary.totalCash,
                totalTint: Color.green.opacity(0.12)
            )

            flowBlock(
                title: "Cash out",
                lines: [
                    (LotterySummaryDisplayName.onlinePayouts, summary.onlineCashes),
                    (LotterySummaryDisplayName.instantPayouts, summary.instantCashes)
                ],
                totalLabel: LotterySummaryDisplayName.totalCashOut,
                totalValue: summary.totalCashes,
                totalTint: Color.red.opacity(0.1)
            )

            netBlock
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

  @ViewBuilder
    private var netBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Net")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            amountRow(
                label: LotterySummaryDisplayName.balanceAfterCashOut,
                value: summary.cashInBag,
                emphasized: false
            )

            if summary.registerCash > 0.005 {
                amountRow(
                    label: LotterySummaryDisplayName.lessRegisterFloat,
                    value: -summary.registerCash,
                    emphasized: false,
                    valueColor: .secondary
                )
            }

            amountRow(
                label: LotterySummaryDisplayName.expectedEnclosedCash,
                value: summary.cashInBagNet,
                emphasized: true
            )

            if let actual = resolvedActualEnclosed {
                Divider()
                amountRow(
                    label: LotterySummaryDisplayName.actualEnclosedCash,
                    value: actual,
                    emphasized: true
                )
            }

            if let variance = resolvedVariance {
                let label = LotterySummaryDisplayName.varianceLabel(for: variance)
                amountRow(
                    label: label,
                    value: variance,
                    emphasized: true,
                    valueColor: variance >= 0 ? .green : .red,
                    showSign: true
                )
            }
        }
        .padding(12)
        .background(Color(red: 0.95, green: 0.95, blue: 1.0))
        .cornerRadius(10)
    }

    private func flowBlock(
        title: String,
        lines: [(String, Double)],
        totalLabel: String,
        totalValue: Double,
        totalTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                amountRow(label: line.0, value: line.1, emphasized: false)
            }

            HStack {
                Text(totalLabel)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                Spacer()
                Text(formatCurrency(totalValue))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(totalTint)
            .cornerRadius(8)
        }
    }

    private func amountRow(
        label: String,
        value: Double,
        emphasized: Bool,
        valueColor: Color = .black,
        showSign: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(formatSignedCurrency(value, showSign: showSign))
                .font(emphasized ? .subheadline.weight(.bold) : .subheadline)
                .foregroundColor(valueColor)
        }
    }

    private func formatSignedCurrency(_ amount: Double, showSign: Bool) -> String {
        if showSign {
            let sign = amount >= 0 ? "+" : "−"
            return "\(sign)\(formatCurrency(abs(amount)))"
        }
        if amount < 0 {
            return "−\(formatCurrency(abs(amount)))"
        }
        return formatCurrency(amount)
    }

    private func formatCurrency(_ amount: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount))
            ?? "$\(String(format: "%.2f", amount))"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
