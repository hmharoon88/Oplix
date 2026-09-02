//
//  LocationPayrollRun.swift
//  Oplix
//
//  Manual payroll runs saved per location (app payroll sheet).
//

import Foundation

struct PayrollRunLine: Codable, Identifiable, Equatable {
    var id: String
    var employeeName: String
    var hourlyRate: Double
    var hours: Double
    var grossPay: Double?
    var loanDeductions: [PayrollLoanDeduction]?
    /// One-off deduction for this pay period only (not a company loan).
    var otherDeductionAmount: Double?
    var otherDeductionDescription: String?
    var pay: Double

    init(
        id: String,
        employeeName: String,
        hourlyRate: Double,
        hours: Double,
        grossPay: Double,
        loanDeductions: [PayrollLoanDeduction] = [],
        otherDeductionAmount: Double = 0,
        otherDeductionDescription: String = "",
        pay: Double
    ) {
        self.id = id
        self.employeeName = employeeName
        self.hourlyRate = hourlyRate
        self.hours = hours
        self.grossPay = grossPay
        self.loanDeductions = loanDeductions.isEmpty ? nil : loanDeductions
        let trimmedNote = otherDeductionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.otherDeductionAmount = otherDeductionAmount > 0.005 ? otherDeductionAmount : nil
        self.otherDeductionDescription = (otherDeductionAmount > 0.005 && !trimmedNote.isEmpty) ? trimmedNote : nil
        self.pay = pay
    }

    var resolvedGrossPay: Double {
        grossPay ?? pay
    }

    var resolvedLoanDeductions: [PayrollLoanDeduction] {
        loanDeductions ?? []
    }

    var totalLoanDeductions: Double {
        resolvedLoanDeductions.reduce(0) { $0 + $1.amount }
    }

    var resolvedOtherDeductionAmount: Double {
        otherDeductionAmount ?? 0
    }

    var resolvedOtherDeductionDescription: String {
        otherDeductionDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var totalAllDeductions: Double {
        totalLoanDeductions + resolvedOtherDeductionAmount
    }
}

struct LocationPayrollRun: Identifiable, Codable, Equatable {
    let id: String
    let locationId: String
    var periodStart: Date
    var periodEnd: Date
    var note: String?
    var lines: [PayrollRunLine]
    var totalPay: Double
    var totalHours: Double
    var totalGrossPay: Double?
    var totalLoanDeductions: Double?
    var createdAt: Date
    var createdSource: String?

    init(
        id: String = UUID().uuidString,
        locationId: String,
        periodStart: Date,
        periodEnd: Date,
        note: String? = nil,
        lines: [PayrollRunLine],
        totalPay: Double,
        totalHours: Double,
        totalGrossPay: Double? = nil,
        totalLoanDeductions: Double? = nil,
        createdAt: Date = Date(),
        createdSource: String? = "ios"
    ) {
        self.id = id
        self.locationId = locationId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.note = note
        self.lines = lines
        self.totalPay = totalPay
        self.totalHours = totalHours
        self.totalGrossPay = totalGrossPay
        self.totalLoanDeductions = totalLoanDeductions
        self.createdAt = createdAt
        self.createdSource = createdSource
    }

    var resolvedTotalGrossPay: Double {
        totalGrossPay ?? lines.reduce(0) { $0 + $1.resolvedGrossPay }
    }

    var resolvedTotalLoanDeductions: Double {
        totalLoanDeductions ?? lines.reduce(0) { $0 + $1.totalLoanDeductions }
    }

    var resolvedTotalOtherDeductions: Double {
        lines.reduce(0) { $0 + $1.resolvedOtherDeductionAmount }
    }
}
