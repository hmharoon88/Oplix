//
//  LotteryShiftSummarySheet.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

/// Review-only summary after the employee closes a lottery shift.
/// Actual enclosed cash is entered on the form before close (Option A).
struct LotteryShiftSummarySheet: View {
    let summary: ShiftSummaryData
    let form: LotteryForm
    let template: LotteryFormTemplate
    let onDismiss: () -> Void

    // Pre-compute beginning and ending numbers for performance
    private var rowNumbers: [String: (beginning: String, ending: String)] {
        var numbers: [String: (beginning: String, ending: String)] = [:]
        for row in template.rows {
            let beginKey = "begin_\(row.id)"
            let endKey = "row_\(row.id)"
            let beginning = form.formData[beginKey]?.isEmpty == false ? form.formData[beginKey]! : "—"
            let ending = form.formData[endKey]?.isEmpty == false ? form.formData[endKey]! : "—"
            numbers[row.id] = (beginning: beginning, ending: ending)
        }
        return numbers
    }

    private var lotteryItems: [(String, String)] {
        [
            ("Total Sold", "\(summary.totalSold)"),
            ("Total Dollars", formatCurrency(Double(summary.totalDollars))),
            ("Total Books", "\(summary.totalBooks)")
        ]
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            Text("Shift Closed")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.black)

                            Text("Summary")
                                .font(.headline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .padding(.top, 40)

                        VStack(spacing: 16) {
                            LotteryCashFlowSummaryView(summary: summary)

                            SummaryCard(
                                title: "Lottery Totals",
                                items: lotteryItems
                            )
                        }
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Beginning & Ending Numbers")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    tableHeaderCell("Bin #")
                                    tableHeaderCell("Begin #")
                                    tableHeaderCell("End #")
                                }
                                .background(Theme.cloudBlue.opacity(0.2))

                                LazyVStack(spacing: 0) {
                                    ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                                        let numbers = rowNumbers[row.id] ?? (beginning: "—", ending: "—")
                                        LotterySummaryRowView(
                                            binNumber: index + 1,
                                            beginningNumber: numbers.beginning,
                                            endingNumber: numbers.ending,
                                            isEven: index % 2 == 0
                                        )
                                    }
                                }
                            }
                            .overlay(
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .leading
                            )
                            .overlay(
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .trailing
                            )
                            .cornerRadius(8)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 8)

                        Button(action: onDismiss) {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.cloudBlue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private func formatCurrency(_ amount: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount))
            ?? "$\(String(format: "%.2f", amount))"
    }

    private func tableHeaderCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.cloudBlue.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
}

// MARK: - Optimized Row View for Summary Table
struct LotterySummaryRowView: View {
    let binNumber: Int
    let beginningNumber: String
    let endingNumber: String
    let isEven: Bool

    private var columnWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16 * 2
        let availableWidth = screenWidth - padding
        return availableWidth / 3
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(binNumber)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
                .background(isEven ? Theme.cloudWhite : Color.white)
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(.gray.opacity(0.5)),
                    alignment: .trailing
                )
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(.gray.opacity(0.5)),
                    alignment: .leading
                )

            Text(beginningNumber)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
                .background(isEven ? Theme.cloudWhite : Color.white)
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(.gray.opacity(0.5)),
                    alignment: .trailing
                )

            Text(endingNumber)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .frame(width: columnWidth, height: 44)
                .background(isEven ? Theme.cloudWhite : Color.white)
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(.gray.opacity(0.5)),
                    alignment: .trailing
                )
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .bottom
        )
    }
}

// MARK: - Summary Card Component
struct SummaryCard: View {
    let title: String
    let items: [(String, String)]
    var highlightColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.0)
                        .font(.subheadline)
                        .foregroundColor(.black)
                    Spacer()
                    Text(item.1)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(highlightColor ?? .black)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }
}
