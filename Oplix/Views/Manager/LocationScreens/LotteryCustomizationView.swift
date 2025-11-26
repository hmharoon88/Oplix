//
//  LotteryCustomizationView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotteryCustomizationView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var formRows: [LotteryFormTemplateRow] = []
    @State private var rowToDelete: LotteryFormTemplateRow?
    @State private var showingDeleteConfirmation = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Done button
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.leading)
                    
                    Spacer()
                    
                    Text("Lottery Form Customization")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Save") {
                        Task {
                            await saveTemplate()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.trailing)
                    .disabled(isSaving)
                    .overlay(
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                    )
                }
                .frame(height: 60)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.3, blue: 0.6),
                            Color(red: 0.15, green: 0.4, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Add/Delete Buttons
                HStack(spacing: 16) {
                    Button(action: {
                        formRows.append(LotteryFormTemplateRow())
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Row")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.cloudBlue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if let row = rowToDelete {
                            showingDeleteConfirmation = true
                        } else if !formRows.isEmpty {
                            rowToDelete = formRows.last
                            showingDeleteConfirmation = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "minus.circle.fill")
                            Text("Delete Row")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(rowToDelete != nil ? Color.red : Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(formRows.isEmpty)
                    
                    Spacer()
                }
                .padding()
                .background(Theme.cloudWhite)
                
                // Lottery Form Table - fits on screen
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Header Row
                        HStack(spacing: 0) {
                            headerCell("Bin #")
                            headerCell("Game #")
                            headerCell("Value")
                            headerCell("Tickets")
                            headerCell("Begin #")
                            headerCell("End #")
                            headerCell("Sold")
                            headerCell("Dollar")
                            headerCell("Books")
                        }
                        .background(Theme.cloudBlue.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.5)),
                            alignment: .bottom
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.5)),
                            alignment: .top
                        )
                        
                        // Data Rows
                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading template...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(Theme.cloudWhite)
                        } else if formRows.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No rows yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Tap 'Add Row' to create a new row")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(Theme.cloudWhite)
                        } else {
                            ForEach(Array($formRows.enumerated()), id: \.element.id) { index, $row in
                                HStack(spacing: 0) {
                                    // Bin# column - auto-populated with serial number (read-only)
                                    binNumberCell(String(index + 1))
                                    dataCell($row.gameNumber)
                                    dataCell($row.value)
                                    dataCell($row.tickets)
                                    dataCell($row.beginningNumber)
                                    dataCell($row.endingNumber)
                                    dataCell($row.sold)
                                    dataCell($row.dollar)
                                    dataCell($row.books)
                                }
                                .background(rowToDelete?.id == row.id ? Color.red.opacity(0.2) : Theme.cloudWhite)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.gray.opacity(0.5)),
                                    alignment: .bottom
                                )
                                .onTapGesture {
                                    if rowToDelete?.id == row.id {
                                        rowToDelete = nil
                                    } else {
                                        rowToDelete = row
                                    }
                                }
                            }
                            
                            // Totals Row (non-deletable)
                            HStack(spacing: 0) {
                                totalCell("", isBold: false) // Empty for Bin#
                                totalCell("TOTAL", isBold: true)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell(formatNumber(totalSold), isBold: true)
                                totalCell(formatNumber(totalDollars), isBold: true)
                                totalCell(formatNumber(totalBooks), isBold: true)
                            }
                            .background(Color(red: 0.9, green: 0.9, blue: 0.95))
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(Theme.cloudBlue),
                                alignment: .top
                            )
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .bottom
                            )
                        }
                    }
                    .overlay(
                        // Left border for entire table
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .leading
                    )
                    .overlay(
                        // Right border for entire table
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .trailing
                    )
                }
                .background(Theme.cloudWhite)
            }
        }
        .alert("Delete Row", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                rowToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let row = rowToDelete {
                    formRows.removeAll { $0.id == row.id }
                    rowToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this row?")
        }
        .onAppear {
            Task {
                await loadTemplate()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func loadTemplate() async {
        isLoading = true
        formRows = await viewModel.loadLotteryFormTemplate()
        isLoading = false
    }
    
    private func saveTemplate() async {
        isSaving = true
        errorMessage = nil
        showingError = false
        
        do {
            try await viewModel.saveLotteryFormTemplate(rows: formRows)
            isSaving = false
            dismiss()
        } catch {
            errorMessage = "Failed to save template: \(error.localizedDescription)"
            showingError = true
            isSaving = false
        }
    }
    
    private var columnWidth: CGFloat {
        // Calculate width to fit 9 columns on screen
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16 // Side padding
        let availableWidth = screenWidth - padding * 2
        return availableWidth / 9
    }
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.black)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudBlue.opacity(0.1))
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border (only for first cell)
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func binNumberCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func dataCell(_ binding: Binding<String>) -> some View {
        TextField("", text: Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                // Only allow numeric characters and single decimal point
                var filtered = ""
                var hasDecimal = false
                for char in newValue {
                    if char.isNumber {
                        filtered.append(char)
                    } else if char == "." && !hasDecimal {
                        filtered.append(char)
                        hasDecimal = true
                    }
                }
                binding.wrappedValue = filtered
            }
        ))
        .keyboardType(.decimalPad)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 11))
        .foregroundColor(.black)
        .frame(width: columnWidth, height: 44)
        .background(Theme.cloudWhite)
        .overlay(
            // Right border
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .trailing
        )
        .overlay(
            // Left border (only for first cell)
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .leading
        )
    }
    
    private func totalCell(_ text: String, isBold: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: isBold ? .bold : .regular))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Color(red: 0.9, green: 0.9, blue: 0.95))
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    // Computed properties for totals
    private var totalSold: Double {
        formRows.compactMap { Double($0.sold) }.reduce(0, +)
    }
    
    private var totalDollars: Double {
        formRows.compactMap { Double($0.dollar) }.reduce(0, +)
    }
    
    private var totalBooks: Double {
        formRows.compactMap { Double($0.books) }.reduce(0, +)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value == 0 {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
}

#Preview {
    LotteryCustomizationView(viewModel: LocationDetailViewModel(userId: "test", locationId: "test"))
}

