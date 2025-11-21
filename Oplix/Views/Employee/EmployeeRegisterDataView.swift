//
//  EmployeeRegisterDataView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeRegisterDataView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @State private var cashSale: String = ""
    @State private var cashInHand: String = ""
    @State private var overShort: String = ""
    @State private var creditCard: String = ""
    @State private var expenseDescriptions: [String] = [""]
    @State private var expenseAmounts: [String] = [""]
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if let shift = viewModel.currentShift {
                ScrollView {
                    VStack(spacing: 20) {
                        ShiftRegisterEntryCard(
                            shift: shift,
                            cashSale: $cashSale,
                            cashInHand: $cashInHand,
                            overShort: $overShort,
                            creditCard: $creditCard,
                            expenseDescriptions: $expenseDescriptions,
                            expenseAmounts: $expenseAmounts,
                            onSave: {
                                Task {
                                    await saveRegisterData(shift: shift)
                                }
                            }
                        )
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Active Shift")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("You need to clock in to enter register data")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Register Data")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Configure navigation bar appearance for visible text
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            
            if let shift = viewModel.currentShift {
                initializeRegisterData(from: shift)
            }
        }
        .onChange(of: viewModel.currentShift) { oldValue, newValue in
            if let shift = newValue {
                initializeRegisterData(from: shift)
            }
        }
        .onChange(of: cashSale) { oldValue, newValue in
            calculateOverShort()
        }
        .onChange(of: cashInHand) { oldValue, newValue in
            calculateOverShort()
        }
    }
    
    private func initializeRegisterData(from shift: Shift) {
        cashSale = shift.cashSale.map { String(format: "%.2f", $0) } ?? ""
        cashInHand = shift.cashInHand.map { String(format: "%.2f", $0) } ?? ""
        creditCard = shift.creditCard.map { String(format: "%.2f", $0) } ?? ""
        
        // Initialize expense fields from existing expenses
        if shift.expenses.isEmpty {
            expenseDescriptions = [""]
            expenseAmounts = [""]
        } else {
            expenseDescriptions = shift.expenses.map { $0.description }
            expenseAmounts = shift.expenses.map { String(format: "%.2f", $0.amount) }
        }
        
        // Calculate over/short automatically
        calculateOverShort()
    }
    
    private func calculateOverShort() {
        let sale = Double(cashSale) ?? 0.0
        let inHand = Double(cashInHand) ?? 0.0
        let calculated = inHand - sale
        overShort = String(format: "%.2f", calculated)
    }
    
    private func saveRegisterData(shift: Shift) async {
        var updatedShift = shift
        updatedShift.cashSale = Double(cashSale)
        updatedShift.cashInHand = Double(cashInHand)
        // Over/Short is calculated automatically
        updatedShift.overShort = Double(overShort)
        updatedShift.creditCard = Double(creditCard)
        
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
        
        await viewModel.updateShift(updatedShift)
    }
}

