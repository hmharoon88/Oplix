//
//  ReportBriefSummaryBuilder.swift
//  Oplix
//

import Foundation

enum ReportBriefSummaryBuilder {
    static func build(
        type: ReportType,
        lottery: LotteryReportContent?,
        payroll: PayrollReportContent?,
        register: RegisterReportContent?
    ) -> ReportBriefSummary {
        switch type {
        case .lottery:
            guard let c = lottery else {
                return empty("No lottery data")
            }
            let s = c.summary
            return ReportBriefSummary(
                headline: "\(s.closeCount) close\(s.closeCount == 1 ? "" : "s") · \(ReportFormatting.currency(s.totalSold)) sold",
                metrics: [
                    ReportMetric(label: "Closes", value: "\(s.closeCount)"),
                    ReportMetric(label: "Total sold", value: ReportFormatting.currency(s.totalSold)),
                    ReportMetric(label: "Expected enclosed", value: ReportFormatting.currency(s.totalExpectedEnclosed)),
                    ReportMetric(label: "Actual enclosed", value: ReportFormatting.currency(s.totalActualEnclosed)),
                    ReportMetric(label: "Net over/short", value: ReportFormatting.currency(s.netOverShort)),
                    ReportMetric(label: "Employees", value: "\(c.employeeSections.count)")
                ]
            )

        case .payroll:
            guard let c = payroll else {
                return empty("No payroll data")
            }
            let s = c.summary
            return ReportBriefSummary(
                headline: "\(s.employeeCount) employee\(s.employeeCount == 1 ? "" : "s") · \(ReportFormatting.currency(s.totalPay)) total pay",
                metrics: [
                    ReportMetric(label: "Employees", value: "\(s.employeeCount)"),
                    ReportMetric(label: "Total hours", value: ReportFormatting.hours(s.totalHours)),
                    ReportMetric(label: "Total pay", value: ReportFormatting.currency(s.totalPay)),
                    ReportMetric(label: "Shifts", value: "\(s.shiftCount)")
                ]
            )

        case .register:
            guard let c = register else {
                return empty("No register data")
            }
            let s = c.summary
            return ReportBriefSummary(
                headline: "\(ReportFormatting.currency(s.totalSales)) sales · \(ReportFormatting.currency(s.netTotal)) net",
                metrics: [
                    ReportMetric(label: "Total sales", value: ReportFormatting.currency(s.totalSales)),
                    ReportMetric(label: "Total expenses", value: ReportFormatting.currency(s.totalExpenses)),
                    ReportMetric(label: "Net", value: ReportFormatting.currency(s.netTotal)),
                    ReportMetric(label: "Register over/short", value: ReportFormatting.currency(s.totalOverShort)),
                    ReportMetric(label: "Shifts", value: "\(s.shiftCount)"),
                    ReportMetric(label: "Employees", value: "\(c.employeeSections.count)")
                ]
            )
        }
    }

    private static func empty(_ headline: String) -> ReportBriefSummary {
        ReportBriefSummary(headline: headline, metrics: [])
    }
}
