//
//  PackReturnsBreakdownView.swift
//  Oplix
//

import SwiftUI

/// Line-item list of pack returns for shift reports and inventory.
struct PackReturnsBreakdownView: View {
    let title: String
    let lines: [LotteryPackReturnLineItem]
    var footerNote: String? = nil

    private var totalDollars: Double {
        lines.reduce(0) { $0 + $1.returnedDollars }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Text(formatCurrency(totalDollars))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell("Bin", width: 36)
                    headerCell("Game", width: 48)
                    headerCell("Val", width: 40)
                    headerCell("Pack", minWidth: 64)
                    headerCell("Tk", width: 36)
                    headerCell("$", width: 52, alignment: .trailing)
                }
                .background(Theme.cloudBlue.opacity(0.15))

                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    HStack(spacing: 0) {
                        bodyCell(line.binNumber, width: 36)
                        bodyCell(line.gameNumber.isEmpty ? "—" : line.gameNumber, width: 48)
                        bodyCell(line.formattedValue, width: 40)
                        bodyCell(line.packSerial.isEmpty ? "—" : line.packSerial, minWidth: 64)
                        bodyCell("\(line.returnedTickets)", width: 36)
                        bodyCell(formatCurrency(line.returnedDollars), width: 52, alignment: .trailing)
                    }
                    .background(index % 2 == 0 ? Theme.cloudWhite : Color.white)
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )

            if let footerNote, !footerNote.isEmpty {
                Text(footerNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private func headerCell(_ text: String, width: CGFloat? = nil, minWidth: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .frame(maxWidth: minWidth != nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
            .frame(minWidth: minWidth, alignment: alignment)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
    }

    private func bodyCell(_ text: String, width: CGFloat? = nil, minWidth: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: minWidth != nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
            .frame(minWidth: minWidth, alignment: alignment)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
