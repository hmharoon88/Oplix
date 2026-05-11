//
//  LotteryShiftSummarySheet.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryShiftSummarySheet: View {
    let summary: ShiftSummaryData
    let form: LotteryForm
    let template: LotteryFormTemplate
    let onDismiss: () -> Void
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var cashInHandValue: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @FocusState private var isCashInHandFocused: Bool
    
    // Computed property to calculate over/short
    private var calculatedOverShort: Double? {
        guard let cashInHand = Double(cashInHandValue) else { return nil }
        let shiftEndCash = summary.cashInBagNet
        return cashInHand - shiftEndCash
    }
    
    // Formatted over/short display
    private var overShortDisplay: String {
        guard let overShort = calculatedOverShort else { return "—" }
        let sign = overShort >= 0 ? "+" : ""
        return "\(sign)\(formatCurrency(overShort))"
    }
    
    // Over/short label (Over or Short)
    private var overShortLabel: String {
        guard let overShort = calculatedOverShort else { return "Over/Short" }
        return overShort >= 0 ? "Over" : "Short"
    }
    
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
    
    // Pre-compute formatted values once
    private var lotteryItems: [(String, String)] {
        [
            ("Total Sold", "\(summary.totalSold)"),
            ("Total Dollars", formatCurrency(Double(summary.totalDollars))),
            ("Total Books", "\(summary.totalBooks)")
        ]
    }
    
    private var cashItems: [(String, String)] {
        [
            ("Register Cash", formatCurrency(summary.registerCash)),
            ("Total Cash", formatCurrency(summary.totalCash)),
            ("Remaining Cash", formatCurrency(summary.cashInBag)),
            ("Shift End Cash", formatCurrency(summary.cashInBagNet))
        ]
    }
    
    private var onlineInstantItems: [(String, String)] {
        [
            ("Online Total", formatCurrency(summary.onlineTotal)),
            ("Instant Total", formatCurrency(summary.instantTotal)),
            ("Online Cashes", formatCurrency(summary.onlineCashes)),
            ("Instant Cashes", formatCurrency(summary.instantCashes)),
            ("Total Cashes", formatCurrency(summary.totalCashes))
        ]
    }
    
    private var totalSoldItems: [(String, String)] {
        [
            ("Amount", formatCurrency(summary.totalSoldAmount))
        ]
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Shift Closed Successfully")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text("Summary")
                                .font(.headline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .padding(.top, 40)

                        // Summary Cards — pulled above the begin/end
                        // numbers table so the most relevant numbers
                        // (totals + cash in hand entry) are visible
                        // immediately when the sheet appears, without
                        // scrolling past the per-row table first.
                        VStack(spacing: 16) {
                            // Lottery Totals
                            SummaryCard(
                                title: "Lottery Totals",
                                items: lotteryItems
                            )

                            // Cash Totals
                            SummaryCard(
                                title: "Cash Totals",
                                items: cashItems
                            )

                            // Online & Instant
                            SummaryCard(
                                title: "Online & Instant",
                                items: onlineInstantItems
                            )

                            // Total Sold Amount
                            SummaryCard(
                                title: "Total Sold Amount",
                                items: totalSoldItems,
                                highlightColor: .green
                            )

                            // Cash in Hand Input Field
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Cash in Hand")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                
                                HStack {
                                    Text("$")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                    
                                    TextField("0.00", text: $cashInHandValue)
                                        .keyboardType(.numbersAndPunctuation)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                        .focused($isCashInHandFocused)
                                        .onTapGesture {
                                            isCashInHandFocused = true
                                        }
                                        .onChange(of: cashInHandValue) { oldValue, newValue in
                                            // Allow only numbers, decimal point, and minus sign at the start
                                            let filtered = newValue.filter { char in
                                                char.isNumber || char == "." || char == "-"
                                            }
                                            // Only allow minus at the start
                                            if filtered.contains("-") && !filtered.hasPrefix("-") {
                                                cashInHandValue = oldValue
                                            } else {
                                                cashInHandValue = filtered
                                            }
                                        }
                                }
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(cashInHandValue.isEmpty ? Color.red.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isCashInHandFocused = true
                                }
                                
                                if cashInHandValue.isEmpty {
                                    Text("Please enter cash in hand amount before closing")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                // Display calculated Over/Short
                                if !cashInHandValue.isEmpty, let overShort = calculatedOverShort {
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    HStack {
                                        Text(overShortLabel)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        Text(overShortDisplay)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(overShort >= 0 ? .green : .red)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding()
                            .background(Theme.cloudWhite)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)

                        // Beginning and Ending Numbers Table — moved
                        // below the summary cards so users see the
                        // headline totals first and the per-row detail
                        // for reference / verification afterwards.
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Beginning & Ending Numbers")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                // Header Row
                                HStack(spacing: 0) {
                                    tableHeaderCell("Bin #")
                                    tableHeaderCell("Begin #")
                                    tableHeaderCell("End #")
                                }
                                .background(Theme.cloudBlue.opacity(0.2))

                                // Data Rows - Use LazyVStack for better scrolling performance
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

                        // Close Button
                        Button(action: {
                            Task {
                                await saveCashInHandAndDismiss()
                            }
                        }) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(isSaving ? "Saving..." : "Close")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(cashInHandValue.isEmpty ? Color.gray : Theme.cloudBlue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .disabled(cashInHandValue.isEmpty || isSaving)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Prevent going back if cash in hand is not entered
                        if !cashInHandValue.isEmpty {
                            Task {
                                await saveCashInHandAndDismiss()
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(cashInHandValue.isEmpty ? .gray : .blue)
                    }
                    .disabled(cashInHandValue.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isCashInHandFocused = false
                    }
                }
            }
        }
    }
    
    // Cache the formatter for better performance
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    private func formatCurrency(_ amount: Double) -> String {
        return Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private func saveCashInHandAndDismiss() async {
        guard !cashInHandValue.isEmpty else {
            await MainActor.run {
                errorMessage = "Please enter cash in hand amount before closing"
                showingError = true
            }
            return
        }
        
        // Parse the cash in hand value
        guard let cashInHand = Double(cashInHandValue) else {
            await MainActor.run {
                errorMessage = "Please enter a valid number"
                showingError = true
            }
            return
        }
        
        // Calculate over/short: cashInHand - shiftEndCash
        let shiftEndCash = summary.cashInBagNet
        let overShort = cashInHand - shiftEndCash
        
        isSaving = true
        
        do {
            // Update the lottery form with calculated over/short value
            try await viewModel.updateLotteryFormOverShort(formId: form.id, overShort: overShort)
            
            // Dismiss after successful save
            await MainActor.run {
                isSaving = false
                onDismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = "Failed to save cash in hand: \(error.localizedDescription)"
                showingError = true
            }
        }
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
        let padding: CGFloat = 16 * 2 // Side padding
        let availableWidth = screenWidth - padding
        return availableWidth / 3
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Bin #
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
            
            // Begin #
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
            
            // End #
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

// MARK: - Summary Card
struct SummaryCard: View {
    let title: String
    let items: [(String, String)]
    var highlightColor: Color? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(highlightColor ?? Theme.cloudBlue)
                .padding(.bottom, 4)
            
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.0)
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                    
                    Spacer()
                    
                    Text(item.1)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(highlightColor ?? .black)
                }
                
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .drawingGroup() // Optimize rendering for static content
    }
}

