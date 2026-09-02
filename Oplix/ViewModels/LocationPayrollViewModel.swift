//
//  LocationPayrollViewModel.swift
//  Oplix
//
//  Manual payroll sheet: hours entry, loan deductions, period dates, saved runs, print text.
//

import Foundation
import SwiftUI

@MainActor
final class LocationPayrollViewModel: ObservableObject {
    @Published var periodStart: Date = Calendar.current.startOfDay(for: Date())
    @Published var periodEnd: Date = Calendar.current.startOfDay(for: Date())
    @Published var hoursText: [String: String] = [:]
    @Published var loanDeductionText: [String: [String: String]] = [:]
    @Published var otherDeductionAmountText: [String: String] = [:]
    @Published var otherDeductionDescriptionText: [String: String] = [:]
    @Published var note: String = ""
    @Published var pastRuns: [LocationPayrollRun] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let userId: String
    let locationId: String
    private let firebaseService = FirebaseService.shared
    private var employees: [Employee] = []

    init(userId: String, locationId: String) {
        self.userId = userId
        self.locationId = locationId
    }

    func load(employees: [Employee], locationName: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        self.employees = employees.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var enriched: [Employee] = []
        for var employee in self.employees {
            employee = await enrichFromManagerRecord(employee)
            enriched.append(employee)
        }
        self.employees = enriched

        do {
            pastRuns = try await firebaseService.fetchPayrollRuns(userId: userId, locationId: locationId)
            applySuggestedPeriod(from: pastRuns.first)
        } catch {
            errorMessage = error.localizedDescription
        }

        _ = locationName
    }

    /// Payroll uses the location employee list, but loans (and rates) are
    /// maintained on the manager-level employee record — merge so deductions show.
    private func enrichFromManagerRecord(_ employee: Employee) async -> Employee {
        var merged = employee
        do {
            let managerEmployee = try await firebaseService.fetchManagerEmployee(
                userId: userId,
                employeeId: employee.id
            )
            if let loans = managerEmployee.loans, !loans.isEmpty {
                merged.loans = loans.map { EmployeeLoan.preparedForPayroll($0) }
            } else if let loans = merged.loans, !loans.isEmpty {
                merged.loans = loans.map { EmployeeLoan.preparedForPayroll($0) }
            }
            if merged.hourlyRate == nil {
                merged.hourlyRate = managerEmployee.hourlyRate
            }
        } catch {
            if var loans = merged.loans, !loans.isEmpty {
                merged.loans = loans.map { EmployeeLoan.preparedForPayroll($0) }
            }
        }
        return merged
    }

    private func applySuggestedPeriod(from lastRun: LocationPayrollRun?) {
        let calendar = Calendar.current
        if let last = lastRun {
            let lastEnd = calendar.startOfDay(for: last.periodEnd)
            periodStart = calendar.date(byAdding: .day, value: 1, to: lastEnd) ?? lastEnd
        } else {
            periodStart = calendar.startOfDay(for: Date())
        }
        periodEnd = calendar.startOfDay(for: Date())
        if periodEnd < periodStart {
            periodEnd = periodStart
        }
    }

    struct DraftLine: Identifiable {
        let id: String
        let name: String
        let hourlyRate: Double?
        let activeLoans: [EmployeeLoan]
        var hours: Double
        var grossPay: Double
        var loanDeductions: [PayrollLoanDeduction]
        var otherDeductionAmount: Double
        var otherDeductionDescription: String
        var totalLoanDeductions: Double
        var totalDeductions: Double
        var netPay: Double
    }

    var draftLines: [DraftLine] {
        employees.map { employee in
            let hours = parsedHours(for: employee.id)
            let rate = employee.hourlyRate ?? 0
            let gross = hours * rate
            let loans = employee.activeLoans
            let deductions = loans.compactMap { loan -> PayrollLoanDeduction? in
                let amount = parsedLoanDeduction(employeeId: employee.id, loanId: loan.id)
                guard amount > 0 else { return nil }
                return PayrollLoanDeduction(from: loan, amount: amount)
            }
            let loanTotal = deductions.reduce(0) { $0 + $1.amount }
            let otherAmount = parsedOtherDeductionAmount(for: employee.id)
            let otherNote = otherDeductionDescriptionText[employee.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let totalDeductions = loanTotal + otherAmount
            let net = max(0, gross - totalDeductions)
            return DraftLine(
                id: employee.id,
                name: employee.name,
                hourlyRate: employee.hourlyRate,
                activeLoans: loans,
                hours: hours,
                grossPay: gross,
                loanDeductions: deductions,
                otherDeductionAmount: otherAmount,
                otherDeductionDescription: otherNote,
                totalLoanDeductions: loanTotal,
                totalDeductions: totalDeductions,
                netPay: net
            )
        }
    }

    var totalHours: Double {
        draftLines.reduce(0) { $0 + $1.hours }
    }

    var totalGrossPay: Double {
        draftLines.reduce(0) { $0 + $1.grossPay }
    }

    var totalLoanDeductions: Double {
        draftLines.reduce(0) { $0 + $1.totalLoanDeductions }
    }

    var totalOtherDeductions: Double {
        draftLines.reduce(0) { $0 + $1.otherDeductionAmount }
    }

    var totalPay: Double {
        draftLines.reduce(0) { $0 + $1.netPay }
    }

    var hasAnyHours: Bool {
        draftLines.contains { $0.hours > 0 }
    }

    func bindingHours(for employeeId: String) -> Binding<String> {
        Binding(
            get: { self.hoursText[employeeId] ?? "" },
            set: { self.hoursText[employeeId] = $0 }
        )
    }

    func bindingLoanDeduction(employeeId: String, loanId: String) -> Binding<String> {
        Binding(
            get: { self.loanDeductionText[employeeId]?[loanId] ?? "" },
            set: { newValue in
                var perEmployee = self.loanDeductionText[employeeId] ?? [:]
                perEmployee[loanId] = newValue
                self.loanDeductionText[employeeId] = perEmployee
            }
        )
    }

    func bindingOtherDeductionAmount(for employeeId: String) -> Binding<String> {
        Binding(
            get: { self.otherDeductionAmountText[employeeId] ?? "" },
            set: { self.otherDeductionAmountText[employeeId] = $0 }
        )
    }

    func bindingOtherDeductionDescription(for employeeId: String) -> Binding<String> {
        Binding(
            get: { self.otherDeductionDescriptionText[employeeId] ?? "" },
            set: { self.otherDeductionDescriptionText[employeeId] = $0 }
        )
    }

    func parsedHours(for employeeId: String) -> Double {
        guard let raw = hoursText[employeeId]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return 0 }
        return Double(raw) ?? 0
    }

    func parsedLoanDeduction(employeeId: String, loanId: String) -> Double {
        guard let raw = loanDeductionText[employeeId]?[loanId]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return 0 }
        return Double(raw) ?? 0
    }

    func parsedOtherDeductionAmount(for employeeId: String) -> Double {
        guard let raw = otherDeductionAmountText[employeeId]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return 0 }
        return max(0, Double(raw) ?? 0)
    }

    func savePayrollRun(locationName: String) async {
        guard periodEnd >= periodStart else {
            errorMessage = "Pay-through date must be on or after the period start."
            return
        }
        guard hasAnyHours else {
            errorMessage = "Enter hours for at least one employee."
            return
        }

        let payableLines = draftLines.filter { $0.hours > 0 }
        if let validationError = validate(lines: payableLines) {
            errorMessage = validationError
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        let calendar = Calendar.current
        let lines = payableLines.map { line in
            PayrollRunLine(
                id: line.id,
                employeeName: line.name,
                hourlyRate: line.hourlyRate ?? 0,
                hours: line.hours,
                grossPay: line.grossPay,
                loanDeductions: line.loanDeductions,
                otherDeductionAmount: line.otherDeductionAmount,
                otherDeductionDescription: line.otherDeductionDescription,
                pay: line.netPay
            )
        }

        let run = LocationPayrollRun(
            locationId: locationId,
            periodStart: calendar.startOfDay(for: periodStart),
            periodEnd: calendar.startOfDay(for: periodEnd),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
            lines: lines,
            totalPay: totalPay,
            totalHours: totalHours,
            totalGrossPay: totalGrossPay,
            totalLoanDeductions: totalLoanDeductions
        )

        do {
            try await firebaseService.savePayrollRun(userId: userId, locationId: locationId, run: run)
            try await applyLoanBalances(from: lines)
            pastRuns.insert(run, at: 0)
            hoursText = [:]
            loanDeductionText = [:]
            otherDeductionAmountText = [:]
            otherDeductionDescriptionText = [:]
            note = ""
            applySuggestedPeriod(from: run)

            var booksNote = ""
            do {
                try await BooksService.shared.syncPayrollRunToBooks(
                    userId: userId,
                    locationId: locationId,
                    run: run
                )
                booksNote = " Net pay synced to Daily books."
            } catch {
                booksNote = " Daily books were not updated (\(error.localizedDescription))."
            }
            successMessage = "Payroll saved for \(Self.formatPeriod(start: run.periodStart, end: run.periodEnd)).\(booksNote)"
        } catch {
            errorMessage = error.localizedDescription
        }

        _ = locationName
    }

    private func validate(lines: [DraftLine]) -> String? {
        for line in lines {
            if line.totalDeductions > line.grossPay + 0.009 {
                return "\(line.name): deductions cannot exceed gross pay."
            }
            if line.otherDeductionAmount > 0.005,
               line.otherDeductionDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(line.name): enter a description for the other deduction."
            }
            guard let employee = employees.first(where: { $0.id == line.id }) else { continue }
            for deduction in line.loanDeductions {
                guard let loan = employee.activeLoans.first(where: { $0.id == deduction.id }) else { continue }
                if deduction.amount > loan.amountDue + 0.009 {
                    let limitLabel = loan.hasHadDeduction ? "remaining balance" : "loan amount"
                    return "\(line.name): \(loan.label) deduction exceeds \(limitLabel) (\(Self.formatCurrency(loan.amountDue)))."
                }
            }
        }
        return nil
    }

    private func applyLoanBalances(from lines: [PayrollRunLine]) async throws {
        for line in lines where !line.resolvedLoanDeductions.isEmpty {
            // Always patch the manager-level record so we don't overwrite
            // schedule/rate/permissions from a stale location copy.
            var managerEmployee = try await firebaseService.fetchManagerEmployee(
                userId: userId,
                employeeId: line.id
            )
            var employeeLoans = (managerEmployee.loans ?? []).map { EmployeeLoan.preparedForPayroll($0) }

            for deduction in line.resolvedLoanDeductions {
                guard let loanIndex = employeeLoans.firstIndex(where: { $0.id == deduction.id }) else { continue }
                employeeLoans[loanIndex].remainingBalance = max(
                    0,
                    employeeLoans[loanIndex].remainingBalance - deduction.amount
                )
                if employeeLoans[loanIndex].remainingBalance < 0.01 {
                    employeeLoans[loanIndex].remainingBalance = 0
                    employeeLoans[loanIndex].isActive = false
                }
            }

            managerEmployee.loans = employeeLoans
            try await firebaseService.updateManagerEmployee(userId: userId, employee: managerEmployee)

            let locationIds = Set(managerEmployee.assignedLocationIds + [locationId])
            for locId in locationIds {
                var locationEmployee = managerEmployee
                locationEmployee.locationId = locId
                try await firebaseService.updateEmployee(
                    userId: userId,
                    locationId: locId,
                    employee: locationEmployee
                )
            }

            if let index = employees.firstIndex(where: { $0.id == line.id }) {
                employees[index].loans = employeeLoans
            }
        }
    }

    func printableText(locationName: String, run: LocationPayrollRun? = nil) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: run?.periodStart ?? periodStart)
        let end = calendar.startOfDay(for: run?.periodEnd ?? periodEnd)
        let lines = run?.lines ?? draftLines.filter { $0.hours > 0 }.map {
            PayrollRunLine(
                id: $0.id,
                employeeName: $0.name,
                hourlyRate: $0.hourlyRate ?? 0,
                hours: $0.hours,
                grossPay: $0.grossPay,
                loanDeductions: $0.loanDeductions,
                otherDeductionAmount: $0.otherDeductionAmount,
                otherDeductionDescription: $0.otherDeductionDescription,
                pay: $0.netPay
            )
        }
        let sheetNote = run?.note ?? (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
        let hoursTotal = run?.totalHours ?? totalHours
        let grossTotal = run?.resolvedTotalGrossPay ?? totalGrossPay
        let loanDeductionTotal = run?.resolvedTotalLoanDeductions ?? totalLoanDeductions
        let otherDeductionTotal = run?.resolvedTotalOtherDeductions ?? totalOtherDeductions
        let payTotal = run?.totalPay ?? totalPay

        var out = """
        PAYROLL
        \(locationName)
        Period: \(Self.formatPeriod(start: start, end: end))
        Printed: \(Self.formatDateTime(Date()))

        """
        out += String(format: "%-18@ %7@ %7@ %10@ %10@\n", "Employee", "Rate", "Hours", "Gross", "Net")
        out += String(repeating: "-", count: 58) + "\n"

        for line in lines.sorted(by: { $0.employeeName.localizedCaseInsensitiveCompare($1.employeeName) == .orderedAscending }) {
            let rate = line.hourlyRate > 0 ? Self.formatCurrency(line.hourlyRate) + "/hr" : "—"
            out += String(
                format: "%-18@ %7@ %7.2f %10@ %10@\n",
                line.employeeName,
                rate,
                line.hours,
                Self.formatCurrency(line.resolvedGrossPay),
                Self.formatCurrency(line.pay)
            )
            for deduction in line.resolvedLoanDeductions {
                out += String(
                    format: "  - %-18@ %@\n",
                    deduction.label,
                    Self.formatCurrency(deduction.amount)
                )
            }
            if line.resolvedOtherDeductionAmount > 0.005 {
                let label = line.resolvedOtherDeductionDescription.isEmpty
                    ? "Other deduction"
                    : line.resolvedOtherDeductionDescription
                out += String(
                    format: "  - %-18@ %@\n",
                    label,
                    Self.formatCurrency(line.resolvedOtherDeductionAmount)
                )
            }
        }

        out += "\n"
        out += "Total hours: \(String(format: "%.2f", hoursTotal))\n"
        out += "Gross pay: \(Self.formatCurrency(grossTotal))\n"
        if loanDeductionTotal > 0 {
            out += "Loan deductions: \(Self.formatCurrency(loanDeductionTotal))\n"
        }
        if otherDeductionTotal > 0 {
            out += "Other deductions: \(Self.formatCurrency(otherDeductionTotal))\n"
        }
        out += "Net pay: \(Self.formatCurrency(payTotal))\n"

        if let sheetNote, !sheetNote.isEmpty {
            out += "\nNote:\n\(sheetNote)\n"
        }

        return out
    }

    static func formatPeriod(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    static func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}
