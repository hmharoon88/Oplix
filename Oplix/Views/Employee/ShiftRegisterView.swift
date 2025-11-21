//
//  ShiftRegisterView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ShiftRegisterView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let shift: Shift
    @Environment(\.dismiss) var dismiss
    
    @State private var cashSale: String = ""
    @State private var cashInHand: String = ""
    @State private var overShort: String = ""
    @State private var creditCard: String = ""
    @State private var expenses: [Expense] = []
    @State private var showingAddExpense = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(viewModel: EmployeeHomeViewModel, shift: Shift) {
        self.viewModel = viewModel
        self.shift = shift
        // Pre-fill existing values if any
        _cashSale = State(initialValue: shift.cashSale.map { String(format: "%.2f", $0) } ?? "")
        _cashInHand = State(initialValue: shift.cashInHand.map { String(format: "%.2f", $0) } ?? "")
        _overShort = State(initialValue: shift.overShort.map { String(format: "%.2f", $0) } ?? "")
        _creditCard = State(initialValue: shift.creditCard.map { String(format: "%.2f", $0) } ?? "")
        _expenses = State(initialValue: shift.expenses)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Cash Register") {
                        TextField("Cash Sale", text: $cashSale)
                            .keyboardType(.decimalPad)
                        TextField("Cash In Hand", text: $cashInHand)
                            .keyboardType(.decimalPad)
                        TextField("Over/Short", text: $overShort)
                            .keyboardType(.decimalPad)
                    }
                    
                    Section("Credit Card") {
                        TextField("Credit Card Amount", text: $creditCard)
                            .keyboardType(.decimalPad)
                    }
                    
                    Section("Expenses") {
                        ForEach(expenses) { expense in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(expense.description)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(expense.timestamp, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatCurrency(expense.amount))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                        }
                        .onDelete { indexSet in
                            expenses.remove(atOffsets: indexSet)
                        }
                        
                        Button(action: {
                            showingAddExpense = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Expense")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                    Section {
                        Text("Enter the register amounts for this shift. Over/Short can be negative if there's a shortage.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Shift Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveRegisterData()
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView(expenses: $expenses)
            }
        }
    }
    
    private func saveRegisterData() async {
        var updatedShift = shift
        
        updatedShift.cashSale = Double(cashSale)
        updatedShift.cashInHand = Double(cashInHand)
        updatedShift.overShort = Double(overShort)
        updatedShift.creditCard = Double(creditCard)
        updatedShift.expenses = expenses
        
        await viewModel.updateShift(updatedShift)
        
        if viewModel.errorMessage == nil {
            dismiss()
        } else {
            errorMessage = viewModel.errorMessage ?? "Failed to save register data"
            showingError = true
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

// MARK: - Add Expense View
struct AddExpenseView: View {
    @Binding var expenses: [Expense]
    @Environment(\.dismiss) var dismiss
    @State private var description = ""
    @State private var amount = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Expense Details") {
                        TextField("Description", text: $description)
                            .textInputAutocapitalization(.sentences)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExpense()
                    }
                    .disabled(description.isEmpty || amount.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addExpense() {
        guard !description.isEmpty, !amount.isEmpty else {
            errorMessage = "Please enter description and amount"
            showingError = true
            return
        }
        
        guard let expenseAmount = Double(amount), expenseAmount > 0 else {
            errorMessage = "Please enter a valid amount"
            showingError = true
            return
        }
        
        let expense = Expense(description: description, amount: expenseAmount)
        expenses.append(expense)
        dismiss()
    }
}

