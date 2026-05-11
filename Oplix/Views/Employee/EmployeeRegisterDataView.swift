//
//  EmployeeRegisterDataView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

// Helper struct for register data in UI
struct RegisterData: Identifiable {
    let id: String
    var cashSale: String
    var cashInHand: String
    var cashExpenseDescriptions: [String] // Multiple cash expense descriptions
    var cashExpenseAmounts: [String] // Multiple cash expense amounts
    var creditCard: String
    var fuelSaleGallons: String
    var fuelSaleDollars: String
    
    init(id: String = UUID().uuidString, cashSale: String = "", cashInHand: String = "", cashExpenseDescriptions: [String] = [""], cashExpenseAmounts: [String] = [""], creditCard: String = "", fuelSaleGallons: String = "", fuelSaleDollars: String = "") {
        self.id = id
        self.cashSale = cashSale
        self.cashInHand = cashInHand
        self.cashExpenseDescriptions = cashExpenseDescriptions
        self.cashExpenseAmounts = cashExpenseAmounts
        self.creditCard = creditCard
        self.fuelSaleGallons = fuelSaleGallons
        self.fuelSaleDollars = fuelSaleDollars
    }
}

struct EmployeeRegisterDataView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var registers: [RegisterData] = [RegisterData()]
    @State private var expenseDescriptions: [String] = [""]
    @State private var expenseAmounts: [String] = [""]
    @State private var savedRegisterIds: Set<String> = [] // Track which registers have been saved
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLastRegisterExpanded = false // Track if last register card is expanded
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Show last closed register for location (from any employee)
                    // Only show if it's not the current employee's active shift
                    if let lastClose = viewModel.lastLocationRegisterClose,
                       let closedAt = lastClose.registerClosedAt {
                        // Don't show if it's the current employee's active shift (they're entering new data)
                        let isCurrentEmployeeActiveShift = lastClose.employeeId == viewModel.employeeId && lastClose.isActive
                        if !isCurrentEmployeeActiveShift {
                            LastLocationRegisterCard(
                                shift: lastClose,
                                isExpanded: $isLastRegisterExpanded,
                                employeeName: getEmployeeName(for: lastClose.employeeId)
                            )
                            .padding(.horizontal)
                        }
                    }
                    
                    ShiftRegisterEntryCard(
                        shift: viewModel.currentShift ?? createPlaceholderShift(),
                        registers: $registers,
                        expenseDescriptions: $expenseDescriptions,
                        expenseAmounts: $expenseAmounts,
                        savedRegisterIds: savedRegisterIds,
                        isReadOnly: false, // Always allow editing when reopened
                        onSave: {
                            Task {
                                await saveRegisterData()
                            }
                        }
                    )
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                if !errorMessage.isEmpty {
                    dismiss()
                }
            }
        } message: {
            Text(errorMessage)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load last location register close when view appears
            if let managerUserId = viewModel.managerUserId {
                await viewModel.loadLastLocationRegisterClose(managerUserId: managerUserId, locationId: viewModel.locationId)
            }
        }
        .onAppear {
            // Check if employee is clocked in
            if viewModel.currentShift?.isActive != true {
                errorMessage = "You must be clocked in to enter register data. Please clock in first."
                showingError = true
            }
            // Configure navigation bar appearance for visible text
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            // Configure TextField placeholder text color for better visibility
            UITextField.appearance().attributedPlaceholder = NSAttributedString(
                string: "",
                attributes: [.foregroundColor: UIColor.gray.withAlphaComponent(0.8)]
            )
            
            if let shift = viewModel.currentShift {
                // If register was previously closed, start fresh with empty fields
                if shift.registerClosedAt != nil {
                    // Start with empty fields for new entry
                    registers = [RegisterData()]
                    expenseDescriptions = [""]
                    expenseAmounts = [""]
                    savedRegisterIds = []
                } else {
                    // Load existing data if register hasn't been closed
                    initializeRegisterData(from: shift)
                }
            } else {
                // Initialize with empty data if no shift exists
                registers = [RegisterData()]
                expenseDescriptions = [""]
                expenseAmounts = [""]
            }
        }
        .onChange(of: viewModel.currentShift) { oldValue, newValue in
            if let shift = newValue {
                // If register was previously closed, start fresh with empty fields
                if shift.registerClosedAt != nil {
                    // Start with empty fields for new entry
                    registers = [RegisterData()]
                    expenseDescriptions = [""]
                    expenseAmounts = [""]
                    savedRegisterIds = []
                } else {
                    // Load existing data if register hasn't been closed
                    initializeRegisterData(from: shift)
                }
            }
        }
    }
    
    private func initializeRegisterData(from shift: Shift) {
        // Initialize registers from shift
        if shift.registers.isEmpty {
            // If no registers in shift, check legacy fields
            if shift.cashSale != nil || shift.cashInHand != nil || shift.creditCard != nil {
                // Convert legacy single register to new format
                registers = [RegisterData(
                    cashSale: shift.cashSale.map { String(format: "%.2f", $0) } ?? "",
                    cashInHand: shift.cashInHand.map { String(format: "%.2f", $0) } ?? "",
                    cashExpenseDescriptions: [""],
                    cashExpenseAmounts: [""],
                    creditCard: shift.creditCard.map { String(format: "%.2f", $0) } ?? "",
                    fuelSaleGallons: "",
                    fuelSaleDollars: ""
                )]
            } else {
                registers = [RegisterData()]
            }
        } else {
            registers = shift.registers.map { register in
                // Convert single cash expense to array format (for backward compatibility)
                var cashExpenseDescriptions: [String] = [""]
                var cashExpenseAmounts: [String] = [""]
                
                if let expense = register.cashExpense, expense > 0 {
                    cashExpenseDescriptions = [register.cashExpenseDescription ?? ""]
                    cashExpenseAmounts = [String(format: "%.2f", expense)]
                }
                
                return RegisterData(
                    id: register.id,
                    cashSale: register.cashSale.map { String(format: "%.2f", $0) } ?? "",
                    cashInHand: register.cashInHand.map { String(format: "%.2f", $0) } ?? "",
                    cashExpenseDescriptions: cashExpenseDescriptions,
                    cashExpenseAmounts: cashExpenseAmounts,
                    creditCard: register.creditCard.map { String(format: "%.2f", $0) } ?? "",
                    fuelSaleGallons: register.fuelSaleGallons.map { String(format: "%.2f", $0) } ?? "",
                    fuelSaleDollars: register.fuelSaleDollars.map { String(format: "%.2f", $0) } ?? ""
                )
            }
        }
        
        // Initialize expense fields from existing expenses
        if shift.expenses.isEmpty {
            expenseDescriptions = [""]
            expenseAmounts = [""]
        } else {
            expenseDescriptions = shift.expenses.map { $0.description }
            expenseAmounts = shift.expenses.map { String(format: "%.2f", $0.amount) }
        }
    }
    
    private func createPlaceholderShift() -> Shift {
        // Create a placeholder shift for display purposes when no shift exists
        return Shift(
            id: UUID().uuidString,
            employeeId: viewModel.employeeId,
            locationId: viewModel.locationId,
            clockInTime: nil,
            clockOutTime: nil,
            assignedAt: nil,
            acknowledged: false,
            scheduledStartTime: nil,
            scheduledEndTime: nil,
            isAutoClockedOut: false,
            startedLate: false,
            manuallyClockedOut: true
        )
    }
    
    private func saveRegisterData() async {
        // Require an active shift (employee must be clocked in)
        guard let shift = viewModel.currentShift, shift.isActive else {
            await MainActor.run {
                errorMessage = "You must be clocked in to save register data. Please clock in first."
                showingError = true
            }
            return
        }
        
        var updatedShift = shift
        
        // Convert registers to Register objects with calculated overShort
        // Note: Cash expense is added to cash in hand for calculation
        updatedShift.registers = registers.map { registerData in
            let sale = Double(registerData.cashSale) ?? 0.0
            let inHand = Double(registerData.cashInHand) ?? 0.0
            
            // Sum all cash expenses
            let totalCashExpense = registerData.cashExpenseAmounts.compactMap { Double($0) }.reduce(0, +)
            
            // Cash expense is added to cash in hand for over/short calculation
            let adjustedCashInHand = inHand + totalCashExpense
            let calculatedOverShort = adjustedCashInHand - sale
            
            // Store all cash expense descriptions and amounts
            let descriptions = registerData.cashExpenseDescriptions.filter { !$0.isEmpty }
            let amounts = registerData.cashExpenseAmounts.compactMap { Double($0) }.filter { $0 > 0 }
            
            // For backward compatibility, store the total cash expense and first description
            let firstDescription = descriptions.first ?? ""
            
            return Register(
                id: registerData.id,
                cashSale: Double(registerData.cashSale),
                cashInHand: Double(registerData.cashInHand),
                cashExpense: totalCashExpense > 0 ? totalCashExpense : nil,
                cashExpenseDescription: firstDescription.isEmpty ? nil : firstDescription,
                cashExpenseDescriptions: descriptions.isEmpty ? nil : descriptions,
                cashExpenseAmounts: amounts.isEmpty ? nil : amounts,
                overShort: calculatedOverShort,
                creditCard: Double(registerData.creditCard),
                fuelSaleGallons: Double(registerData.fuelSaleGallons),
                fuelSaleDollars: Double(registerData.fuelSaleDollars)
            )
        }
        
        // For backward compatibility, also set legacy fields from first register
        if let firstRegister = registers.first {
            updatedShift.cashSale = Double(firstRegister.cashSale)
            updatedShift.cashInHand = Double(firstRegister.cashInHand)
            updatedShift.creditCard = Double(firstRegister.creditCard)
            // Calculate over/short (include cash expenses)
            let sale = Double(firstRegister.cashSale) ?? 0.0
            let inHand = Double(firstRegister.cashInHand) ?? 0.0
            let totalCashExpense = firstRegister.cashExpenseAmounts.compactMap { Double($0) }.reduce(0, +)
            updatedShift.overShort = (inHand + totalCashExpense) - sale
        }
        
        // Convert expense fields to Expense objects (only non-empty ones)
        updatedShift.expenses = []
        for (index, description) in expenseDescriptions.enumerated() {
            if !description.isEmpty && index < expenseAmounts.count {
                if let amount = Double(expenseAmounts[index]), amount > 0 {
                    let expense = Expense(
                        description: description,
                        amount: amount,
                        timestamp: Date()
                    )
                    updatedShift.expenses.append(expense)
                }
            }
        }
        
        // Set register closed timestamp
        updatedShift.registerClosedAt = Date()
        
        // Update the existing shift (we already verified it exists and is active)
        await viewModel.updateShift(updatedShift)
        
        // Mark all current registers as saved
        savedRegisterIds = Set(registers.map { $0.id })
        
        // Small delay to ensure shift is reloaded before dismissing
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Dismiss the view after saving
        dismiss()
    }
    
    private func getEmployeeName(for employeeId: String) -> String {
        // Try to get employee name from viewModel's allEmployees if available
        if let employee = viewModel.allEmployees.first(where: { $0.id == employeeId }) {
            return employee.name
        }
        return "Employee"
    }
}

// Collapsible card showing last closed register for location
struct LastLocationRegisterCard: View {
    let shift: Shift
    @Binding var isExpanded: Bool
    let employeeName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Register Closed")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        if let closedAt = shift.registerClosedAt {
                            Text(closedAt, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(closedAt, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("by \(employeeName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    // Display all registers
                    if shift.registers.isEmpty {
                        // Legacy single register format
                        if shift.cashSale != nil || shift.creditCard != nil {
                            RegisterDetailRow(label: "Cash Sale", value: formatCurrency(shift.cashSale ?? 0))
                            RegisterDetailRow(label: "Credit Card", value: formatCurrency(shift.creditCard ?? 0))
                            if let fuelDollars = shift.registers.first?.fuelSaleDollars ?? nil {
                                RegisterDetailRow(label: "Fuel Sale (Gallons)", value: String(format: "%.2f", shift.registers.first?.fuelSaleGallons ?? 0))
                                RegisterDetailRow(label: "Fuel Sale (Dollars)", value: formatCurrency(fuelDollars))
                            }
                            if let cashInHand = shift.cashInHand {
                                RegisterDetailRow(label: "Cash in Hand", value: formatCurrency(cashInHand))
                            }
                            if let overShort = shift.overShort {
                                RegisterDetailRow(label: "Over/Short", value: formatCurrency(overShort))
                            }
                        }
                    } else {
                        // Multiple registers
                        ForEach(Array(shift.registers.enumerated()), id: \.element.id) { index, register in
                            VStack(alignment: .leading, spacing: 8) {
                                if shift.registers.count > 1 {
                                    Text("Register \(index + 1)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .padding(.top, index > 0 ? 12 : 0)
                                }
                                
                                RegisterDetailRow(label: "Cash Sale", value: formatCurrency(register.cashSale ?? 0))
                                RegisterDetailRow(label: "Credit Card", value: formatCurrency(register.creditCard ?? 0))
                                
                                if let fuelGallons = register.fuelSaleGallons, fuelGallons > 0 {
                                    RegisterDetailRow(label: "Fuel Sale (Gallons)", value: String(format: "%.2f", fuelGallons))
                                }
                                if let fuelDollars = register.fuelSaleDollars, fuelDollars > 0 {
                                    RegisterDetailRow(label: "Fuel Sale (Dollars)", value: formatCurrency(fuelDollars))
                                }
                                
                                if let cashInHand = register.cashInHand {
                                    RegisterDetailRow(label: "Cash in Hand", value: formatCurrency(cashInHand))
                                }
                                
                                // Cash expenses
                                if let descriptions = register.cashExpenseDescriptions,
                                   let amounts = register.cashExpenseAmounts,
                                   !descriptions.isEmpty {
                                    ForEach(Array(zip(descriptions, amounts).enumerated()), id: \.offset) { _, item in
                                        if !item.0.isEmpty && item.1 > 0 {
                                            RegisterDetailRow(
                                                label: "Cash Expense: \(item.0)",
                                                value: formatCurrency(item.1)
                                            )
                                        }
                                    }
                                } else if let expense = register.cashExpense, expense > 0 {
                                    RegisterDetailRow(
                                        label: "Cash Expense: \(register.cashExpenseDescription ?? "")",
                                        value: formatCurrency(expense)
                                    )
                                }
                                
                                if let overShort = register.overShort {
                                    RegisterDetailRow(label: "Over/Short", value: formatCurrency(overShort))
                                }
                            }
                        }
                    }
                    
                    // Non-cash expenses
                    if !shift.expenses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Non-Cash Expenses")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.top, 8)
                            
                            ForEach(shift.expenses, id: \.timestamp) { expense in
                                RegisterDetailRow(
                                    label: expense.description,
                                    value: formatCurrency(expense.amount)
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
            }
        }
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct RegisterDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

