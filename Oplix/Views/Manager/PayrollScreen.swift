//
//  PayrollScreen.swift
//  Oplix
//
//  Manual payroll sheet per location — enter hours, save runs, print.
//

import SwiftUI

struct PayrollScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: LocationDetailViewModel
    @StateObject private var payrollVM: LocationPayrollViewModel
    @State private var printPayload: PayrollPrintPayload?
    @State private var expandedRunId: String?

    init(viewModel: LocationDetailViewModel) {
        self.viewModel = viewModel
        _payrollVM = StateObject(wrappedValue: LocationPayrollViewModel(
            userId: viewModel.userId,
            locationId: viewModel.locationId
        ))
    }

    private var locationName: String {
        viewModel.location?.name ?? "Location"
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            if payrollVM.isLoading && payrollVM.pastRuns.isEmpty && payrollVM.draftLines.isEmpty {
                ProgressView("Loading payroll…")
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        periodCard
                        currentSheetCard
                        if !payrollVM.pastRuns.isEmpty {
                            historySection
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Payroll")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.refreshEmployeesForPayroll()
            await payrollVM.load(employees: viewModel.payrollStaff, locationName: locationName)
        }
        .alert("Error", isPresented: Binding(
            get: { payrollVM.errorMessage != nil },
            set: { if !$0 { payrollVM.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { payrollVM.errorMessage = nil }
        } message: {
            Text(payrollVM.errorMessage ?? "")
        }
        .sheet(item: $printPayload) { payload in
            ReportShareSheet(items: [payload.url])
        }
    }

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pay period")
                .font(.headline)

            if let last = payrollVM.pastRuns.first {
                Text("Last paid: \(LocationPayrollViewModel.formatPeriod(start: last.periodStart, end: last.periodEnd))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            DatePicker(
                "From",
                selection: $payrollVM.periodStart,
                displayedComponents: .date
            )
            .environment(\.timeZone, TimeZone.current)

            DatePicker(
                "Pay through",
                selection: $payrollVM.periodEnd,
                in: payrollVM.periodStart...,
                displayedComponents: .date
            )
            .environment(\.timeZone, TimeZone.current)

            Text("Start date is set automatically from your last saved payroll. Choose pay-through date for this run.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    private var currentSheetCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter hours")
                .font(.title3.weight(.semibold))

            if payrollVM.draftLines.isEmpty {
                Text("No staff at this location.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    payrollHeaderRow
                    Divider()
                    ForEach(payrollVM.draftLines) { line in
                        PayrollDraftRow(line: line, payrollVM: payrollVM)
                        Divider()
                    }
                }
                .background(Color.gray.opacity(0.04))
                .cornerRadius(10)

                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(String(format: "%.2f", payrollVM.totalHours)) hrs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if payrollVM.totalLoanDeductions > 0 || payrollVM.totalOtherDeductions > 0 {
                        Text("Gross \(LocationPayrollViewModel.formatCurrency(payrollVM.totalGrossPay))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if payrollVM.totalLoanDeductions > 0 {
                            Text("− Loans \(LocationPayrollViewModel.formatCurrency(payrollVM.totalLoanDeductions))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if payrollVM.totalOtherDeductions > 0 {
                            Text("− Other \(LocationPayrollViewModel.formatCurrency(payrollVM.totalOtherDeductions))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    Text(LocationPayrollViewModel.formatCurrency(payrollVM.totalPay))
                        .font(.title3.weight(.bold))
                        .foregroundColor(.green)
                    Text("Net pay")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                }
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Note (optional)")
                    .font(.subheadline.weight(.medium))
                TextField("Check #, memo, etc.", text: $payrollVM.note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            if let success = payrollVM.successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            HStack(spacing: 12) {
                Button {
                    preparePrint(run: nil)
                } label: {
                    Label("Print", systemImage: "printer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!payrollVM.hasAnyHours)

                Button {
                    Task {
                        await payrollVM.savePayrollRun(locationName: locationName)
                        if payrollVM.successMessage != nil {
                            dismiss()
                        }
                    }
                } label: {
                    Group {
                        if payrollVM.isSaving {
                            ProgressView()
                        } else {
                            Text("Save payroll")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.cloudBlue)
                .disabled(!payrollVM.hasAnyHours || payrollVM.isSaving)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    private var payrollHeaderRow: some View {
        HStack {
            Text("Employee")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Rate")
                .frame(width: 64, alignment: .trailing)
            Text("Hours")
                .frame(width: 56, alignment: .trailing)
            Text("Net")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous payroll")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            ForEach(payrollVM.pastRuns) { run in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation {
                            expandedRunId = expandedRunId == run.id ? nil : run.id
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocationPayrollViewModel.formatPeriod(start: run.periodStart, end: run.periodEnd))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("\(String(format: "%.1f", run.totalHours)) hrs · Net \(LocationPayrollViewModel.formatCurrency(run.totalPay))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: expandedRunId == run.id ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if expandedRunId == run.id {
                        ForEach(run.lines) { line in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(line.employeeName)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(String(format: "%.1f", line.hours))h")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(LocationPayrollViewModel.formatCurrency(line.pay))
                                        .font(.caption.weight(.semibold))
                                }
                                if line.totalLoanDeductions > 0 {
                                    ForEach(line.resolvedLoanDeductions) { deduction in
                                        Text("− \(deduction.label): \(LocationPayrollViewModel.formatCurrency(deduction.amount))")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                if line.resolvedOtherDeductionAmount > 0.005 {
                                    let label = line.resolvedOtherDeductionDescription.isEmpty
                                        ? "Other deduction"
                                        : line.resolvedOtherDeductionDescription
                                    Text("− \(label): \(LocationPayrollViewModel.formatCurrency(line.resolvedOtherDeductionAmount))")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        if let runNote = run.note, !runNote.isEmpty {
                            Text("Note: \(runNote)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button {
                            preparePrint(run: run)
                        } label: {
                            Label("Print this period", systemImage: "printer")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Theme.cloudWhite)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private func preparePrint(run: LocationPayrollRun?) {
        let text = payrollVM.printableText(locationName: locationName, run: run)
        let fileName = "payroll-\(locationName.replacingOccurrences(of: " ", with: "-"))-\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            printPayload = PayrollPrintPayload(url: url)
        } catch {
            payrollVM.errorMessage = "Couldn’t prepare print file."
        }
    }
}

private struct PayrollPrintPayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PayrollDraftRow: View {
    @ObservedObject var payrollVM: LocationPayrollViewModel
    let line: LocationPayrollViewModel.DraftLine

    init(line: LocationPayrollViewModel.DraftLine, payrollVM: LocationPayrollViewModel) {
        self.line = line
        self.payrollVM = payrollVM
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(line.name)
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(rateLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 64, alignment: .trailing)

                TextField("0", text: payrollVM.bindingHours(for: line.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)

                Text(LocationPayrollViewModel.formatCurrency(line.netPay))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(line.netPay > 0 ? .green : .secondary)
                    .frame(width: 64, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 8) {
                TextField("Deduction description", text: payrollVM.bindingOtherDeductionDescription(for: line.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("0", text: payrollVM.bindingOtherDeductionAmount(for: line.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            if !line.activeLoans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(line.activeLoans) { loan in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loan.label)
                                    .font(.caption.weight(.medium))
                                Text(loanPayrollSubtitle(loan))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            TextField("Deduct", text: payrollVM.bindingLoanDeduction(employeeId: line.id, loanId: loan.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            if line.totalDeductions > 0 {
                Text("Gross \(LocationPayrollViewModel.formatCurrency(line.grossPay)) − \(LocationPayrollViewModel.formatCurrency(line.totalDeductions))")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var rateLabel: String {
        guard let rate = line.hourlyRate, rate > 0 else { return "—" }
        return LocationPayrollViewModel.formatCurrency(rate)
    }

    private func loanPayrollSubtitle(_ loan: EmployeeLoan) -> String {
        "Remaining \(LocationPayrollViewModel.formatCurrency(loan.amountDue))"
    }
}
