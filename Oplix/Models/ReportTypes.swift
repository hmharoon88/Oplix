//
//  ReportTypes.swift
//  Oplix
//

import Foundation

enum ReportType: String, CaseIterable, Identifiable {
    case lottery
    case payroll
    case register

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lottery: return "Lottery"
        case .payroll: return "Payroll"
        case .register: return "Sales & Expenses"
        }
    }

    var systemImage: String {
        switch self {
        case .lottery: return "ticket.fill"
        case .payroll: return "dollarsign.circle.fill"
        case .register: return "cashregister.fill"
        }
    }
}

enum ReportPeriodPreset: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case monthToDate
    case year
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .monthToDate: return "Month to Date"
        case .year: return "This Year"
        case .custom: return "Custom Range"
        }
    }
}

struct ReportDateInterval {
    let start: Date
    let end: Date

    var isValid: Bool { start <= end }

    static let maxSpanDays = 366
}

// MARK: - Generated report payload

struct ReportMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Short overview shown at the top of preview and PDF.
struct ReportBriefSummary {
    let headline: String
    let metrics: [ReportMetric]
}

struct GeneratedReport {
    let type: ReportType
    let locationName: String
    let organizationName: String?
    let interval: ReportDateInterval
    let generatedAt: Date
    let briefSummary: ReportBriefSummary
    let lottery: LotteryReportContent?
    let payroll: PayrollReportContent?
    let register: RegisterReportContent?
}

struct LotteryReportContent {
    let summary: LotteryReportSummary
    let rows: [LotteryReportRow]
    let employeeSections: [LotteryEmployeeSection]
}

struct LotteryEmployeeSection: Identifiable {
    let id: String
    let employeeName: String
    let closeCount: Int
    let totalSold: Double
    let netOverShort: Double
    let rows: [LotteryReportRow]
}

struct LotteryReportSummary {
    let closeCount: Int
    let totalSold: Double
    let totalExpectedEnclosed: Double
    let totalActualEnclosed: Double
    let netOverShort: Double
}

struct LotteryReportRow: Identifiable {
    let id: String
    let submittedAt: Date
    let terminalLabel: String
    let employeeName: String
    let sold: Double
    let expectedEnclosed: Double
    let actualEnclosed: Double?
    let overShort: Double?
}

struct PayrollReportContent {
    let summary: PayrollReportSummary
    let rows: [PayrollReportRow]
    let employeeSections: [PayrollEmployeeSection]
}

struct PayrollEmployeeSection: Identifiable {
    let id: String
    let employeeName: String
    let hourlyRate: Double
    let hours: Double
    let pay: Double
    let shiftCount: Int
}

struct PayrollReportSummary {
    let employeeCount: Int
    let totalHours: Double
    let totalPay: Double
    let shiftCount: Int
}

struct PayrollReportRow: Identifiable {
    let id: String
    let employeeName: String
    let hourlyRate: Double
    let hours: Double
    let pay: Double
    let shiftCount: Int
}

struct RegisterReportContent {
    let summary: RegisterReportSummary
    let dailyRows: [RegisterDailyRow]
    let shiftRows: [RegisterShiftRow]
    let employeeSections: [RegisterEmployeeSection]
}

struct RegisterEmployeeSection: Identifiable {
    let id: String
    let employeeName: String
    let shiftCount: Int
    let totalSales: Double
    let totalExpenses: Double
    let netTotal: Double
    let totalOverShort: Double
    let shiftRows: [RegisterShiftRow]
}

struct RegisterReportSummary {
    let totalSales: Double
    let totalExpenses: Double
    let netTotal: Double
    let shiftCount: Int
    let totalOverShort: Double
}

struct RegisterDailyRow: Identifiable {
    let id: String
    let date: Date
    let sales: Double
    let expenses: Double
    let shiftCount: Int
}

struct RegisterShiftRow: Identifiable {
    let id: String
    let clockOut: Date
    let employeeName: String
    let sales: Double
    let expenses: Double
    let overShort: Double?
}
