//
//  LotterySelectionView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct LotterySelectionView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingActiveShiftForm = false
    @State private var showingLastShiftSummary = false
    @State private var isLoading = true
    @State private var lastShiftLotteryForm: LotteryForm?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    // Back button at top left
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Two cards at the top
                    VStack(spacing: 24) {
                        // Active Shift Card
                        Button(action: {
                            // Check if employee is clocked in
                            if let currentShift = viewModel.currentShift, currentShift.isActive {
                                showingActiveShiftForm = true
                            } else {
                                // Show error if not clocked in
                                errorMessage = "You must be clocked in to fill out the lottery form. Please clock in first."
                                showingError = true
                            }
                        }) {
                            LotterySelectionCard(
                                title: "Active Shift",
                                subtitle: viewModel.currentShift?.isActive == true ? "Fill out lottery form" : "Clock in required",
                                icon: "ticket.fill",
                                color: viewModel.currentShift?.isActive == true ? .blue : .gray,
                                isEnabled: viewModel.currentShift?.isActive == true
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                        .disabled(viewModel.currentShift?.isActive != true)
                        
                        // Last Shift Card
                        Button(action: {
                            showingLastShiftSummary = true
                        }) {
                            LotterySelectionCard(
                                title: "Last Shift",
                                subtitle: lastShiftLotteryForm != nil ? "View shift summary" : "No previous shift",
                                icon: "clock.arrow.circlepath",
                                color: .orange,
                                isEnabled: lastShiftLotteryForm != nil
                            )
                        }
                        .padding(.horizontal, 20)
                        .disabled(lastShiftLotteryForm == nil)
                    }
                    
                    Spacer()
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingActiveShiftForm) {
            if let template = viewModel.lotteryTemplate, !template.rows.isEmpty {
                EmployeeLotteryFormSheet(viewModel: viewModel, template: template)
            }
        }
        .fullScreenCover(isPresented: $showingLastShiftSummary) {
            if let lastForm = lastShiftLotteryForm, let template = viewModel.lotteryTemplate {
                LastShiftSummarySheet(viewModel: viewModel, lotteryForm: lastForm, template: template)
            }
        }
        .onAppear {
            Task {
                await loadLastShiftLotteryForm()
                isLoading = false
            }
        }
    }
    
    private func loadLastShiftLotteryForm() async {
        guard let managerUserId = viewModel.managerUserId else { return }
        
        do {
            // Fetch all lottery forms for this location
            let allForms = try await FirebaseService.shared.fetchLotteryForms(
                userId: managerUserId,
                locationId: viewModel.locationId
            )
            
            // Get the most recent lottery form from ANY employee at this location
            // The lottery form is location-based and should show the most recent state
            // regardless of which employee is viewing it
            lastShiftLotteryForm = allForms
                .sorted { $0.submittedAt > $1.submittedAt }
                .first
        } catch {
            print("Failed to fetch last shift lottery form: \(error.localizedDescription)")
        }
    }
}

// MARK: - Lottery Selection Card
struct LotterySelectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isEnabled: Bool = true
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(isEnabled ? color : .gray)
                .frame(width: 60, height: 60)
                .background(isEnabled ? color.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isEnabled ? .black : .gray)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(isEnabled ? Theme.darkGray : .gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isEnabled ? color : .gray)
        }
        .padding(20)
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Employee Lottery Form Sheet
struct EmployeeLotteryFormSheet: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let template: LotteryFormTemplate
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                EmployeeLotteryFormView(viewModel: viewModel, template: template)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Last Shift Summary Sheet
struct LastShiftSummarySheet: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    let lotteryForm: LotteryForm
    let template: LotteryFormTemplate
    @Environment(\.dismiss) var dismiss
    @State private var shift: Shift?
    @State private var employeeName: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Last Shift Summary")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text(formatDate(lotteryForm.submittedAt))
                                .font(.subheadline)
                                .foregroundColor(Theme.darkGray)
                            
                            if let name = employeeName {
                                Text("by \(name)")
                                    .font(.caption)
                                    .foregroundColor(Theme.darkGray)
                            }
                        }
                        .padding(.top, 20)
                    
                    // Lottery Form Data Table
                    VStack(spacing: 0) {
                        // Header Row
                        HStack(spacing: 0) {
                            headerCell("Bin #")
                            headerCell("Value")
                            headerCell("Begin #")
                            headerCell("End #")
                        }
                        .background(Theme.cloudBlue.opacity(0.2))
                        
                        // Data Rows
                        ForEach(Array(template.rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 0) {
                                binNumberCell(String(index + 1))
                                readOnlyCell(formatValue(row.value))
                                readOnlyCell(row.beginningNumber)
                                // Get ending number from form data or template
                                readOnlyCell(getEndingNumber(for: row.id))
                            }
                            .background(index % 2 == 0 ? Theme.cloudWhite : Color.white)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .bottom
                            )
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
                    
                    // Shift Summary Report (if available)
                    if let summary = lotteryForm.shiftSummary {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Shift Summary Report")
                                .font(.headline)
                                .foregroundColor(.black)
                            
                            // Template Totals
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Lottery Form Totals")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                ShiftSummaryRow(label: "Total Sold Tickets", value: "\(summary.totalSold)")
                                ShiftSummaryRow(label: "Total Dollars", value: formatCurrency(Double(summary.totalDollars)))
                                ShiftSummaryRow(label: "Total Books", value: "\(summary.totalBooks)")
                            }
                            
                            Divider()
                            
                            // Sales Summary
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sales Summary")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                ShiftSummaryRow(label: "Instant Total", value: formatCurrency(summary.instantTotal))
                                ShiftSummaryRow(label: "Online Total", value: formatCurrency(summary.onlineTotal))
                                ShiftSummaryRow(label: "Total Sold Amount", value: formatCurrency(summary.totalSoldAmount))
                            }
                            
                            Divider()
                            
                            // Cash Summary
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Cash Summary")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                ShiftSummaryRow(label: "Register Cash", value: formatCurrency(summary.registerCash))
                                ShiftSummaryRow(label: "Total Cash", value: formatCurrency(summary.totalCash))
                                ShiftSummaryRow(label: "Online Cashes", value: formatCurrency(summary.onlineCashes))
                                ShiftSummaryRow(label: "Instant Cashes", value: formatCurrency(summary.instantCashes))
                                ShiftSummaryRow(label: "Total Cashes", value: formatCurrency(summary.totalCashes))
                                
                                Divider()
                                
                                ShiftSummaryRow(label: "Remaining Cash", value: formatCurrency(summary.cashInBag), isHighlighted: true)
                                ShiftSummaryRow(label: "Shift End Cash", value: formatCurrency(summary.cashInBagNet), isHighlighted: true, isNet: true)
                                
                                // Over/Short (if available)
                                if let overShort = summary.overShort {
                                    Divider()
                                    ShiftSummaryRow(
                                        label: "Over/Short",
                                        value: formatCurrency(overShort),
                                        isHighlighted: true
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color(red: 0.95, green: 0.95, blue: 1.0))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await loadShiftAndEmployeeName()
            }
        }
    }
    
    private func loadShiftAndEmployeeName() async {
        guard let managerUserId = viewModel.managerUserId else { return }
        
        do {
            // Fetch all shifts for this location to find the shift for this lottery form
            let allLocationShifts = try await FirebaseService.shared.fetchShifts(
                userId: managerUserId,
                locationId: viewModel.locationId
            )
            
            // Find the shift for this lottery form
            shift = allLocationShifts.first { $0.id == lotteryForm.shiftId }
            
            // Get employee name if shift found
            if let shift = shift, let employee = viewModel.allEmployees.first(where: { $0.id == shift.employeeId }) {
                employeeName = employee.name
            } else if let shift = shift {
                // If employee not in allEmployees, try to fetch it
                do {
                    let employee = try await FirebaseService.shared.fetchEmployee(
                        userId: managerUserId,
                        locationId: viewModel.locationId,
                        employeeId: shift.employeeId
                    )
                    employeeName = employee.name
                } catch {
                    print("Failed to fetch employee name: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Failed to fetch shift: \(error.localizedDescription)")
        }
    }
    
    private func getEndingNumber(for rowId: String) -> String {
        // Form data stores ending numbers with key "row_\(rowId)"
        let key = "row_\(rowId)"
        if let endingNumber = lotteryForm.formData[key] {
            return endingNumber
        }
        // Fall back to template if not in form data
        return template.rows.first { $0.id == rowId }?.endingNumber ?? ""
    }
    
    private func headerCell(_ text: String) -> some View {
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
    
    private func binNumberCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
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
            .frame(maxWidth: .infinity, minHeight: 44)
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
    
    private func formatValue(_ value: String) -> String {
        if value.isEmpty {
            return ""
        }
        let cleanValue = value.replacingOccurrences(of: "$", with: "")
        return cleanValue.isEmpty ? "" : "$\(cleanValue)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

// MARK: - Shift Summary Row
struct ShiftSummaryRow: View {
    let label: String
    let value: String
    var isHighlighted: Bool = false
    var isNet: Bool = false
    
    private var netAmount: Double? {
        guard isNet else { return nil }
        let cleaned = value.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(isHighlighted ? .headline : .subheadline)
                .foregroundColor(.black)
            Spacer()
            Text(value)
                .font(isHighlighted ? .headline : .subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isNet ? (netAmount ?? 0 >= 0 ? .green : .red) : .black)
        }
    }
}

