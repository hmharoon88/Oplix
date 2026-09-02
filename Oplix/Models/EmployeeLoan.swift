//
//  EmployeeLoan.swift
//  Oplix
//
//  Company loans owed by an employee, repaid via payroll deductions.
//

import Foundation

struct EmployeeLoan: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var label: String
    var originalAmount: Double
    var remainingBalance: Double
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        label: String,
        originalAmount: Double,
        remainingBalance: Double? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.label = label
        self.originalAmount = originalAmount
        self.remainingBalance = remainingBalance ?? originalAmount
        self.isActive = isActive
    }

    /// True after at least one payroll run deducted from this loan.
    var hasHadDeduction: Bool {
        originalAmount > 0.005 && remainingBalance < originalAmount - 0.009
    }

    /// Amount still owed — used for payroll deduction limits.
    var amountDue: Double {
        max(0, remainingBalance > 0.005 ? remainingBalance : originalAmount)
    }

    var isOpen: Bool {
        isActive && originalAmount > 0.005 && amountDue > 0.005
    }

    /// Keep remaining equal to the total until payroll takes the first deduction.
    /// Active loans with remaining ≈ 0 are treated as unset (not paid off) —
    /// fully repaid loans are deactivated by payroll.
    mutating func syncRemainingWithOriginalIfNeeded() {
        guard originalAmount > 0.005 else {
            remainingBalance = 0
            return
        }
        // Paid-off: payroll sets remaining to 0 and isActive to false.
        if !isActive && remainingBalance < 0.005 { return }
        // Unset remaining on an active loan, or never deducted yet → match total.
        if remainingBalance < 0.005 || !hasHadDeduction {
            remainingBalance = originalAmount
        }
    }

    static func preparedForSave(_ loan: EmployeeLoan) -> EmployeeLoan {
        var copy = loan
        copy.syncRemainingWithOriginalIfNeeded()
        return copy
    }

    static func preparedForPayroll(_ loan: EmployeeLoan) -> EmployeeLoan {
        var copy = loan
        copy.syncRemainingWithOriginalIfNeeded()
        return copy
    }
}

struct PayrollLoanDeduction: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var amount: Double

    init(id: String, label: String, amount: Double) {
        self.id = id
        self.label = label
        self.amount = amount
    }

    init(from loan: EmployeeLoan, amount: Double) {
        self.id = loan.id
        self.label = loan.label
        self.amount = amount
    }
}
