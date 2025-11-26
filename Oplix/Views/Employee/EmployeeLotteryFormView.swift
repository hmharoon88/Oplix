//
//  EmployeeLotteryFormView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EmployeeLotteryFormView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let template: LotteryFormTemplate
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var rowValues: [String: String] = [:] // Track ending numbers by row ID
    
    private var columnWidth: CGFloat {
        // Calculate width to fit 4 columns on screen
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16 // Side padding
        let availableWidth = screenWidth - padding * 2
        return availableWidth / 4
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    headerCell("Bin #")
                    headerCell("Value")
                    headerCell("Begin #")
                    headerCell("End #")
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
                ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 0) {
                        // Bin# - read-only serial number
                        binNumberCell(String(index + 1))
                        // Value - read-only
                        readOnlyCell(row.value)
                        // Begin # - read-only
                        readOnlyCell(row.beginningNumber)
                        // End # - editable
                        editableCell(rowId: row.id, initialValue: rowValues[row.id] ?? row.endingNumber)
                    }
                    .background(Theme.cloudWhite)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .bottom
                    )
                }
            }
            .onAppear {
                // Initialize row values from template
                for row in template.rows {
                    rowValues[row.id] = row.endingNumber
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
        .padding(.horizontal)
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
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(width: columnWidth, height: 44)
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
    
    private func binNumberCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
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
    
    private func readOnlyCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
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
    
    private func editableCell(rowId: String, initialValue: String) -> some View {
        let binding = Binding(
            get: { rowValues[rowId] ?? initialValue },
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
                
                // Update local state immediately
                rowValues[rowId] = filtered
                
                // Save to Firebase (debounced - save after user stops typing)
                Task {
                    // Small delay to debounce rapid typing
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Check if value is still the same (user stopped typing)
                    if rowValues[rowId] == filtered {
                        do {
                            try await viewModel.updateLotteryRowEndingNumber(rowId: rowId, endingNumber: filtered)
                        } catch {
                            await MainActor.run {
                                errorMessage = "Failed to update: \(error.localizedDescription)"
                                showingError = true
                                // Revert on error
                                rowValues[rowId] = initialValue
                            }
                        }
                    }
                }
            }
        )
        
        return TextField("", text: binding)
        .keyboardType(.decimalPad)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 11))
        .foregroundColor(.black)
        .frame(width: columnWidth, height: 44)
        .background(Theme.cloudWhite)
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

