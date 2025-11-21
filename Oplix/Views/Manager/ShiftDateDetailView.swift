//
//  ShiftDateDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ShiftDateDetailView: View {
    let dateGroup: DateGroup
    @ObservedObject var viewModel: LocationDetailViewModel
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: dateGroup.date)
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Date Header
                    VStack(spacing: 8) {
                        Text(dateString)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text("\(dateGroup.shifts.count) shift\(dateGroup.shifts.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.cloudWhite)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Summary Card
                    if !dateGroup.shifts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Summary")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            let totalSales = dateGroup.shifts.compactMap { shift in
                                (shift.cashSale ?? 0) + (shift.creditCard ?? 0)
                            }.reduce(0, +)
                            
                            let totalExpenses = dateGroup.shifts.flatMap { $0.expenses }.reduce(0) { $0 + $1.amount }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Sales")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatCurrency(totalSales))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Total Expenses")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatCurrency(totalExpenses))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Net Total")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                Spacer()
                                Text(formatCurrency(totalSales - totalExpenses))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(totalSales - totalExpenses >= 0 ? .green : .red)
                            }
                        }
                        .padding()
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .padding(.horizontal)
                    }
                    
                    // Individual Shifts
                    ForEach(Array(dateGroup.shifts.enumerated()), id: \.element.id) { index, shift in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shift \(index + 1)")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            ShiftRow(shift: shift, viewModel: viewModel)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Shift Details")
        .navigationBarTitleDisplayMode(.inline)
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

