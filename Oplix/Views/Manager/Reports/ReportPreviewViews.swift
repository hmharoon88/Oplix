//
//  ReportPreviewViews.swift
//  Oplix
//

import SwiftUI

struct ReportGeneratedPreview: View {
    let report: GeneratedReport

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ReportBriefSummaryView(summary: report.briefSummary, locationName: report.locationName, interval: report.interval)

            switch report.type {
            case .lottery:
                if let content = report.lottery {
                    employeeSectionsBlock(
                        title: "By employee",
                        isEmpty: content.employeeSections.isEmpty,
                        emptyMessage: { emptyEmployeeMessage("No lottery closes in this period.") },
                        content: {
                            ForEach(content.employeeSections) { section in
                                LotteryEmployeePreviewSection(section: section)
                            }
                        }
                    )
                }
            case .payroll:
                if let content = report.payroll {
                    employeeSectionsBlock(
                        title: "By employee",
                        isEmpty: content.employeeSections.isEmpty,
                        emptyMessage: { emptyEmployeeMessage("No paid shifts in this period.") },
                        content: {
                            ForEach(content.employeeSections) { section in
                                PayrollEmployeePreviewSection(section: section)
                            }
                        }
                    )
                }
            case .register:
                if let content = report.register {
                    if !content.dailyRows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(content.shiftRows.isEmpty ? "Daily totals (Daily books)" : "Daily totals")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ForEach(content.dailyRows.prefix(5)) { day in
                                RegisterDailyPreviewRow(row: day)
                            }
                            if content.dailyRows.count > 5 {
                                Text("+ \(content.dailyRows.count - 5) more days in PDF")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    employeeSectionsBlock(
                        title: "By employee",
                        isEmpty: content.employeeSections.isEmpty,
                        emptyMessage: {
                            if !content.dailyRows.isEmpty {
                                emptyEmployeeMessage("Totals above are from Daily books. No shift register entries in this period.")
                            } else {
                                emptyEmployeeMessage("No sales or expense data in this period.")
                            }
                        },
                        content: {
                            ForEach(content.employeeSections) { section in
                                RegisterEmployeePreviewSection(section: section)
                            }
                        }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func employeeSectionsBlock<Content: View, Empty: View>(
        title: String,
        isEmpty: Bool,
        @ViewBuilder emptyMessage: () -> Empty,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if isEmpty {
                emptyMessage()
            } else {
                content()
            }
        }
    }

    private func emptyEmployeeMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - Brief summary

struct ReportBriefSummaryView: View {
    let summary: ReportBriefSummary
    let locationName: String
    let interval: ReportDateInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Theme.cloudBlue)

            Text(locationName)
                .font(.headline)
            Text(ReportDateRange.formattedRange(interval))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(summary.headline)
                .font(.subheadline)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.metrics.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(summary.metrics.enumerated()), id: \.offset) { index, metric in
                        ReportMetricRow(label: metric.label, value: metric.value)
                        if index < summary.metrics.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }
        }
    }
}

struct ReportMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Employee sections

struct EmployeePreviewCard<Summary: View, Details: View>: View {
    let employeeName: String
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let details: () -> Details
    let detailCount: Int

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(Theme.cloudBlue)
                Text(employeeName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            summary()

            if detailCount > 0 {
                DisclosureGroup(isExpanded: $isExpanded) {
                    details()
                        .padding(.top, 4)
                } label: {
                    Text("Details (\(detailCount))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.cloudBlue)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cloudWhite)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct LotteryEmployeePreviewSection: View {
    let section: LotteryEmployeeSection

    var body: some View {
        EmployeePreviewCard(
            employeeName: section.employeeName,
            summary: {
                VStack(spacing: 6) {
                    ReportMetricRow(label: "Closes", value: "\(section.closeCount)")
                    ReportMetricRow(label: "Sold", value: ReportFormatting.currency(section.totalSold))
                    ReportMetricRow(label: "Net over/short", value: ReportFormatting.currency(section.netOverShort))
                }
            },
            details: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ReportFormatting.dateTime(row.submittedAt))
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(row.terminalLabel)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Sold \(ReportFormatting.currency(row.sold))")
                                .font(.caption2)
                            if let overShort = row.overShort {
                                Text(ReportFormatting.overShortLabel(overShort))
                                    .font(.caption2)
                                    .foregroundColor(overShort >= 0 ? .green : .red)
                            }
                        }
                        if row.id != section.rows.last?.id {
                            Divider()
                        }
                    }
                }
            },
            detailCount: section.rows.count
        )
    }
}

struct PayrollEmployeePreviewSection: View {
    let section: PayrollEmployeeSection

    var body: some View {
        EmployeePreviewCard(
            employeeName: section.employeeName,
            summary: {
                VStack(spacing: 6) {
                    ReportMetricRow(label: "Rate", value: "\(ReportFormatting.currency(section.hourlyRate))/hr")
                    ReportMetricRow(label: "Hours", value: ReportFormatting.hours(section.hours))
                    ReportMetricRow(label: "Pay", value: ReportFormatting.currency(section.pay))
                    ReportMetricRow(label: "Shifts", value: "\(section.shiftCount)")
                }
            },
            details: { EmptyView() },
            detailCount: 0
        )
    }
}

struct RegisterEmployeePreviewSection: View {
    let section: RegisterEmployeeSection

    var body: some View {
        EmployeePreviewCard(
            employeeName: section.employeeName,
            summary: {
                VStack(spacing: 6) {
                    ReportMetricRow(label: "Shifts", value: "\(section.shiftCount)")
                    ReportMetricRow(label: "Sales", value: ReportFormatting.currency(section.totalSales))
                    ReportMetricRow(label: "Expenses", value: ReportFormatting.currency(section.totalExpenses))
                    ReportMetricRow(label: "Net", value: ReportFormatting.currency(section.netTotal))
                }
            },
            details: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.shiftRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ReportFormatting.dateTime(row.clockOut))
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Sales \(ReportFormatting.currency(row.sales)) · Expenses \(ReportFormatting.currency(row.expenses))")
                                .font(.caption2)
                            if let overShort = row.overShort {
                                Text(ReportFormatting.overShortLabel(overShort))
                                    .font(.caption2)
                                    .foregroundColor(overShort >= 0 ? .green : .red)
                            }
                        }
                        if row.id != section.shiftRows.last?.id {
                            Divider()
                        }
                    }
                }
            },
            detailCount: section.shiftRows.count
        )
    }
}

struct RegisterDailyPreviewRow: View {
    let row: RegisterDailyRow

    var body: some View {
        HStack {
            Text(ReportFormatting.dateOnly(row.date))
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text("\(ReportFormatting.currency(row.sales)) · \(row.shiftCount) shift\(row.shiftCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
