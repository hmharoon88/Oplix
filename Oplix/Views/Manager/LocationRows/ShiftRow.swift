//
//  ShiftRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ShiftRow: View {
    let shift: Shift
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingRegisterData = false
    
    private var employeeName: String {
        viewModel.employees.first(where: { $0.id == shift.employeeId })?.name ?? "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Shift #\(shift.id.prefix(8))")
                            .font(.headline)
                        
                        // Flag indicators
                        if shift.shouldBeFlagged || shift.isFlaggedInHistory {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        // Auto clocked out flag
                        if shift.isAutoClockedOut {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Started late flag
                        if shift.startedLate {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    }
                    Text("Employee: \(employeeName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if shift.isAssigned {
                        Text("Assigned")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    } else if shift.isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        Text("Completed")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    // Acknowledge button for flagged shifts
                    if (shift.shouldBeFlagged || shift.isFlaggedInHistory) && !shift.acknowledged {
                        Button(action: {
                            Task {
                                await viewModel.acknowledgeShift(shift)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Acknowledge")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Clock In")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if shift.startedLate {
                            Text("(Late)")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .fontWeight(.semibold)
                        }
                    }
                    if let clockInTime = shift.clockInTime {
                        Text(clockInTime, style: .time)
                            .font(.subheadline)
                    } else {
                        Text("Not started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let clockOutTime = shift.clockOutTime {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            if shift.isAutoClockedOut {
                                Text("Auto Clock Out")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("Clock Out")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(clockOutTime, style: .time)
                            .font(.subheadline)
                            .foregroundColor(shift.isAutoClockedOut ? .red : .primary)
                    }
                } else if shift.isActive {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("In Progress")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
            }
            
            if let hoursWorked = shift.hoursWorked {
                Text("Hours: \(String(format: "%.2f", hoursWorked))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Register Data Section
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("Register Data")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if shift.hasRegisterData {
                    VStack(alignment: .leading, spacing: 6) {
                        if let cashSale = shift.cashSale {
                            HStack {
                                Text("Cash Sale:")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatCurrency(cashSale))
                                    .foregroundColor(.primary)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                        
                        if let cashInHand = shift.cashInHand {
                            HStack {
                                Text("Cash In Hand:")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatCurrency(cashInHand))
                                    .foregroundColor(.primary)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                        
                        if let overShort = shift.overShort {
                            HStack {
                                Text("Over/Short:")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatCurrency(overShort))
                                    .foregroundColor(overShort >= 0 ? .green : .red)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                        
                    if let creditCard = shift.creditCard {
                        HStack {
                            Text("Credit Card:")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(formatCurrency(creditCard))
                                .foregroundColor(.primary)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                } else {
                    Text("No register data entered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 4)
                }
                
                // Expenses Section
                if !shift.expenses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Expenses")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        ForEach(shift.expenses) { expense in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
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
                            .padding(.vertical, 4)
                        }
                        
                        // Total Expenses
                        let totalExpenses = shift.expenses.reduce(0) { $0 + $1.amount }
                        Divider()
                        HStack {
                            Text("Total Expenses:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(formatCurrency(totalExpenses))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .cloudCard()
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

