//
//  PayrollView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct PayrollView: View {
    let userId: String
    @StateObject private var viewModel: PayrollViewModel
    @Environment(\.dismiss) var dismiss
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: PayrollViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Payroll")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .task {
                    await viewModel.loadData()
                }
        }
    }
    
    private var contentView: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                scrollContent
            }
        }
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                periodSelector
                summaryCards
                payrollList
                errorMessageView
            }
            .padding(.vertical)
        }
    }
    
    private var periodSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Period")
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal)
            
            Picker("Period", selection: $viewModel.selectedPeriod) {
                ForEach([PayrollViewModel.PayrollPeriod.week, .month, .monthToDate, .allTime], id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .oplixSegmentedPickerTint()
            .padding(.horizontal)
            .onChange(of: viewModel.selectedPeriod) {
                Task {
                    await viewModel.loadData()
                }
            }
        }
        .padding(.top)
    }
    
    private var summaryCards: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PayrollSummaryCard(
                    title: "Total Payroll",
                    value: formatCurrency(viewModel.totalPayroll),
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
                
                PayrollSummaryCard(
                    title: "Total Hours",
                    value: String(format: "%.1f", viewModel.totalHours),
                    icon: "clock.fill",
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var payrollList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Employee Payroll")
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal)
            
            if viewModel.payrollData.isEmpty {
                Text("No payroll data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cloudWhite)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                ForEach(viewModel.payrollData) { data in
                    PayrollRow(data: data)
                        .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .padding()
        }
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

struct PayrollSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [color.opacity(0.8), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct PayrollRow: View {
    let data: EmployeePayrollData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.employeeName)
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Text("\(data.locationName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatCurrency(data.totalPay))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("\(data.shiftCount) shift\(data.shiftCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hourly Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(data.hourlyRate))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Hours")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", data.totalHours))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                }
            }
        }
        .padding()
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

#Preview {
    PayrollView(userId: "test-user")
}

