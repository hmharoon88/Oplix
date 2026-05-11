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
    @State private var lotteryRegisterAmount: String = ""
    @State private var reverseOrder: Bool = false
    @State private var validationMessage: String?
    @State private var showingValidationMessage = false
    
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
                
                // Lottery Register Amount and Reverse Order Toggle
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Text("Lottery Register Amount:")
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        TextField("Enter amount", text: $lotteryRegisterAmount)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 200)
                    }
                    .padding(.horizontal)
                    
                    Toggle("Reverse Order", isOn: $reverseOrder)
                        .padding(.horizontal)
                        .onChange(of: reverseOrder) {
                            // Recalculate all rows when reverse order changes
                            for index in formRows.indices {
                                calculateRowValues(for: index)
                            }
                        }
                }
                .padding(.vertical, 12)
                .background(Theme.cloudWhite)
                
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
                        if rowToDelete != nil {
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
                                    dataCell($row.gameNumber, rowIndex: index, isGameNumber: true)
                                    dataCell($row.value, isValueField: true)
                                    dataCell($row.tickets)
                                    dataCell($row.beginningNumber, onUpdate: {
                                        validateAndCalculateRow(for: index)
                                    }, rowIndex: index, isTicketNumber: true)
                                    dataCell($row.endingNumber, onUpdate: {
                                        validateAndCalculateRow(for: index)
                                    }, rowIndex: index, isTicketNumber: true)
                                    // Sold, Dollar, Books are read-only calculated cells
                                    calculatedCell(calculateSold(for: row))
                                    calculatedCell(calculateDollar(for: row))
                                    calculatedCell(calculateBooks(for: row))
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
                                totalCell(formatCurrency(totalDollars), isBold: true)
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
        .alert("Validation", isPresented: $showingValidationMessage) {
            Button("OK") {
                validationMessage = nil
            }
        } message: {
            if let validationMessage = validationMessage {
                Text(validationMessage)
            }
        }
    }
    
    private func loadTemplate() async {
        isLoading = true
        let result = await viewModel.loadLotteryFormTemplate()
        formRows = result.rows
        lotteryRegisterAmount = result.lotteryRegisterAmount
        reverseOrder = result.reverseOrder
        
        // Calculate values for all rows after loading
        for index in formRows.indices {
            calculateRowValues(for: index)
        }
        
        isLoading = false
    }
    
    private func saveTemplate() async {
        isSaving = true
        errorMessage = nil
        showingError = false
        
        do {
            try await viewModel.saveLotteryFormTemplate(rows: formRows, lotteryRegisterAmount: lotteryRegisterAmount, reverseOrder: reverseOrder)
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
    
    private func dataCell(_ binding: Binding<String>, onUpdate: (() -> Void)? = nil, rowIndex: Int? = nil, isTicketNumber: Bool = false, isGameNumber: Bool = false, isValueField: Bool = false) -> some View {
        TextField("", text: Binding(
            get: { 
                if isValueField {
                    // Display with $ sign, but store without
                    let value = binding.wrappedValue
                    if value.isEmpty {
                        return ""
                    }
                    // Remove $ if present, then add it back for display
                    let cleanValue = value.replacingOccurrences(of: "$", with: "")
                    return cleanValue.isEmpty ? "" : "$\(cleanValue)"
                }
                return binding.wrappedValue
            },
            set: { newValue in
                // For value field, remove $ sign before processing
                var cleanValue = newValue
                if isValueField {
                    cleanValue = cleanValue.replacingOccurrences(of: "$", with: "")
                }
                
                // Only allow numeric characters and single decimal point
                var filtered = ""
                var hasDecimal = false
                for char in cleanValue {
                    if char.isNumber {
                        filtered.append(char)
                    } else if char == "." && !hasDecimal {
                        filtered.append(char)
                        hasDecimal = true
                    }
                }
                
                // Normalize "0" to "00" for ticket number fields (since "0" represents the first ticket)
                if isTicketNumber && filtered == "0" {
                    filtered = "00"
                }
                
                // Validate ticket number range (prevent invalid entry, but don't show alert)
                if isTicketNumber, let index = rowIndex, index < formRows.count {
                    let row = formRows[index]
                    if !filtered.isEmpty && filtered != "00" {
                        // Check if tickets value exists
                        if let ticketsInt = Int(row.tickets), ticketsInt > 0 {
                            let maxTicketNumber = ticketsInt - 1
                            if let enteredNum = Int(filtered), enteredNum > maxTicketNumber {
                                // Don't update the value (silently prevent invalid entry)
                                return
                            }
                        }
                    }
                }
                
                binding.wrappedValue = filtered
                // Trigger calculation update
                onUpdate?()
                
                // If this is a game number field, trigger auto-population after a short delay
                if isGameNumber {
                    Task {
                        // Small delay to allow the value to be set
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        if let index = rowIndex, index < formRows.count {
                            await autoPopulateFromGameDatabase(for: index)
                        }
                    }
                }
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
    
    // Read-only calculated cell
    private func calculatedCell(_ value: String) -> some View {
        Text(value)
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
    
    // Calculate values for a specific row (no validation alerts during entry)
    private func validateAndCalculateRow(for index: Int) {
        guard index < formRows.count else { return }
        let row = formRows[index]
        
        // Check if Value and Tickets are present
        let hasValue = !row.value.isEmpty
        let hasTickets = !row.tickets.isEmpty
        let hasBeginning = !row.beginningNumber.isEmpty
        let hasEnding = !row.endingNumber.isEmpty
        
        // Only calculate if we have all required fields
        // No validation alerts - just skip calculation if fields are missing
        guard hasValue && hasTickets && hasBeginning && hasEnding else {
            // Clear calculated values if missing required fields
            formRows[index].sold = ""
            formRows[index].dollar = ""
            formRows[index].books = ""
            return
        }
        
        // Calculate sold and books
        let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        
        // Calculate dollars
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        
        // Update row values (these are stored but not displayed - we calculate on the fly)
        formRows[index].sold = String(sold)
        formRows[index].dollar = String(dollars)
        formRows[index].books = String(books)
    }
    
    // Calculate values for a specific row (without validation, for display)
    private func calculateRowValues(for index: Int) {
        guard index < formRows.count else { return }
        let row = formRows[index]
        
        // Only calculate if we have all required fields
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return
        }
        
        // Calculate sold and books
        let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        
        // Calculate dollars
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        
        // Update row values (these are stored but not displayed - we calculate on the fly)
        formRows[index].sold = String(sold)
        formRows[index].dollar = String(dollars)
        formRows[index].books = String(books)
    }
    
    // Calculate sold for a row (for display)
    private func calculateSold(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        return sold > 0 ? String(sold) : ""
    }
    
    // Calculate dollar for a row (for display)
    private func calculateDollar(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        return dollars > 0 ? formatCurrency(Double(dollars)) : ""
    }
    
    // Calculate books for a row (for display)
    private func calculateBooks(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (_, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        return books > 0 ? String(books) : ""
    }
    
    // Computed properties for totals - only include rows with valid data
    private var totalSold: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, and tickets
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty else {
                return total
            }
            
            let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            return total + Double(sold)
        }
    }
    
    private var totalDollars: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, tickets, and value
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty,
                  !row.value.isEmpty else {
                return total
            }
            
            let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
            return total + Double(dollars)
        }
    }
    
    private var totalBooks: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, and tickets
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty else {
                return total
            }
            
            let (_, books) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            return total + Double(books)
        }
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
    
    private func formatCurrency(_ value: Double) -> String {
        if value == 0 {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: value)) ?? ""
        return formatted.isEmpty ? "" : "$\(formatted)"
    }
    
    // Auto-populate Value and Tickets from game database when game number is entered
    private func autoPopulateFromGameDatabase(for index: Int) async {
        guard index < formRows.count else { return }
        let gameNumber = formRows[index].gameNumber
        
        // Only fetch if game number is not empty
        guard !gameNumber.isEmpty else { return }
        
        do {
            let gameData = try await FirebaseService.shared.fetchGameData(gameNumber: gameNumber)
            
            await MainActor.run {
                if let gameData = gameData {
                    // Auto-populate value and tickets
                    formRows[index].value = gameData.value
                    formRows[index].tickets = gameData.tickets
                    
                    // Recalculate row values
                    calculateRowValues(for: index)
                }
            }
        } catch {
            // Game number not found in database - silently ignore
            print("Game number \(gameNumber) not found in database")
        }
    }
}

#Preview {
    LotteryCustomizationView(viewModel: LocationDetailViewModel(userId: "test", locationId: "test"))
}

