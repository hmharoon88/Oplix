//
//  ReportPDFRenderer.swift
//  Oplix
//

import UIKit

enum ReportPDFRenderer {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48
    private static let footerHeight: CGFloat = 28
    private static let lineHeight: CGFloat = 16
    private static let sectionGap: CGFloat = 20

    private static var pageRect: CGRect {
        CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    }

    private static var contentMaxY: CGFloat {
        pageHeight - margin - footerHeight
    }

    static func renderPDF(report: GeneratedReport) throws -> URL {
        let title = fileBaseName(for: report)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            let canvas = PDFCanvas(context: context)
            canvas.startDocument()
            canvas.drawHeader(report: report)
            canvas.drawBriefSummary(report.briefSummary)

            switch report.type {
            case .lottery:
                if let lottery = report.lottery {
                    canvas.drawLottery(lottery)
                } else {
                    canvas.drawEmptyNote("No lottery data for this period.")
                }
            case .payroll:
                if let payroll = report.payroll {
                    canvas.drawPayroll(payroll)
                } else {
                    canvas.drawEmptyNote("No payroll data for this period.")
                }
            case .register:
                if let register = report.register {
                    canvas.drawRegister(register)
                } else {
                    canvas.drawEmptyNote("No register data for this period.")
                }
            }

            canvas.finishCurrentPage()
        }

        try data.write(to: url)
        return url
    }

    // MARK: - Canvas

    private final class PDFCanvas {
        private let context: UIGraphicsPDFRendererContext
        private var y: CGFloat = margin
        private var pageNumber = 0
        private var continuationTitle: String?

        init(context: UIGraphicsPDFRendererContext) {
            self.context = context
        }

        func startDocument() {
            beginPage()
        }

        func finishCurrentPage() {
            drawFooter()
        }

        private func beginPage() {
            context.beginPage(withBounds: pageRect, pageInfo: [:])
            pageNumber += 1
            y = margin

            if pageNumber > 1, let title = continuationTitle {
                y = drawText(
                    "\(title) (continued)",
                    font: .boldSystemFont(ofSize: 12),
                    color: .darkGray
                ) + 8
            }
        }

        /// Starts a new page when the next block would cross the footer area.
        private func beginPageIfNeeded(requiredHeight: CGFloat) {
            guard requiredHeight > 0 else { return }
            if y + requiredHeight <= contentMaxY { return }
            finishCurrentPage()
            beginPage()
        }

        func drawHeader(report: GeneratedReport) {
            continuationTitle = "\(report.type.displayName) · \(report.locationName)"
            y = drawText("Oplix Report", font: .boldSystemFont(ofSize: 22))
            y = drawText(report.type.displayName, font: .boldSystemFont(ofSize: 16)) + 4
            if let org = report.organizationName, !org.isEmpty {
                y = drawText(org, font: .systemFont(ofSize: 12), color: .darkGray) + 2
            }
            y = drawText("Location: \(report.locationName)", font: .systemFont(ofSize: 12)) + 8
            y = drawText("Period: \(ReportDateRange.formattedRange(report.interval))", font: .systemFont(ofSize: 12)) + 2
            y = drawText(
                "Generated: \(ReportFormatting.dateTime(report.generatedAt))",
                font: .systemFont(ofSize: 11),
                color: .gray
            ) + 2
            y += sectionGap
        }

        func drawBriefSummary(_ summary: ReportBriefSummary) {
            drawSectionTitle("At a glance")
            y = drawText(summary.headline, font: .boldSystemFont(ofSize: 12)) + 6
            for metric in summary.metrics {
                drawKeyValue(metric.label, value: metric.value)
            }
            y += sectionGap
        }

        func drawLottery(_ content: LotteryReportContent) {
            if content.employeeSections.isEmpty {
                drawEmptyNote("No lottery closes in this period.")
                return
            }

            for section in content.employeeSections {
                drawEmployeeBlockTitle(section.employeeName)
                drawKeyValue("Closes", value: "\(section.closeCount)", indent: 8)
                drawKeyValue("Sold", value: ReportFormatting.currency(section.totalSold), indent: 8)
                drawKeyValue("Net over/short", value: ReportFormatting.currency(section.netOverShort), indent: 8)
                y += 6
                drawSubsectionTitle("Details")
                for row in section.rows {
                    beginPageIfNeeded(requiredHeight: estimatedLotteryRowHeight(row))
                    y = drawText(ReportFormatting.dateTime(row.submittedAt), font: .boldSystemFont(ofSize: 10))
                    y = drawText(row.terminalLabel, font: .systemFont(ofSize: 9), color: .darkGray) + 2
                    drawKeyValue("Sold", value: ReportFormatting.currency(row.sold), indent: 16)
                    drawKeyValue("Expected enclosed", value: ReportFormatting.currency(row.expectedEnclosed), indent: 16)
                    if let actual = row.actualEnclosed {
                        drawKeyValue("Actual enclosed", value: ReportFormatting.currency(actual), indent: 16)
                    }
                    if let overShort = row.overShort {
                        drawKeyValue(
                            LotterySummaryDisplayName.varianceLabel(for: overShort),
                            value: ReportFormatting.currency(abs(overShort)),
                            indent: 16
                        )
                    }
                    y += 8
                }
                y += sectionGap
            }
        }

        func drawPayroll(_ content: PayrollReportContent) {
            if content.employeeSections.isEmpty {
                drawEmptyNote("No paid shifts in this period.")
                return
            }

            for section in content.employeeSections {
                drawEmployeeBlockTitle(section.employeeName)
                drawKeyValue("Rate", value: ReportFormatting.currency(section.hourlyRate) + "/hr", indent: 8)
                drawKeyValue("Hours", value: ReportFormatting.hours(section.hours), indent: 8)
                drawKeyValue("Pay", value: ReportFormatting.currency(section.pay), indent: 8)
                drawKeyValue("Shifts", value: "\(section.shiftCount)", indent: 8)
                y += sectionGap
            }
        }

        func drawRegister(_ content: RegisterReportContent) {
            if !content.dailyRows.isEmpty {
                let dailyTitle = content.shiftRows.isEmpty
                    ? "Daily totals (Daily books)"
                    : "Daily totals (location)"
                drawSectionTitle(dailyTitle)
                for row in content.dailyRows {
                    beginPageIfNeeded(requiredHeight: 4 * lineHeight + 8)
                    y = drawText(ReportFormatting.dateOnly(row.date), font: .boldSystemFont(ofSize: 11))
                    y += 4
                    drawKeyValue("Sales", value: ReportFormatting.currency(row.sales), indent: 8)
                    drawKeyValue("Expenses", value: ReportFormatting.currency(row.expenses), indent: 8)
                    if row.shiftCount > 0 {
                        drawKeyValue("Shifts", value: "\(row.shiftCount)", indent: 8)
                    }
                    y += 8
                }
                y += sectionGap
            }

            if content.employeeSections.isEmpty {
                if content.dailyRows.isEmpty {
                    drawEmptyNote("No sales or expense data in this period.")
                } else {
                    drawEmptyNote("Totals above are from Daily books. No shift register entries in this period.")
                }
                return
            }

            for section in content.employeeSections {
                drawEmployeeBlockTitle(section.employeeName)
                drawKeyValue("Shifts", value: "\(section.shiftCount)", indent: 8)
                drawKeyValue("Sales", value: ReportFormatting.currency(section.totalSales), indent: 8)
                drawKeyValue("Expenses", value: ReportFormatting.currency(section.totalExpenses), indent: 8)
                drawKeyValue("Net", value: ReportFormatting.currency(section.netTotal), indent: 8)
                drawKeyValue("Over/short", value: ReportFormatting.currency(section.totalOverShort), indent: 8)
                y += 6
                drawSubsectionTitle("Shift details")
                for row in section.shiftRows {
                    beginPageIfNeeded(requiredHeight: 5 * lineHeight + 10)
                    y = drawText(ReportFormatting.dateTime(row.clockOut), font: .boldSystemFont(ofSize: 10))
                    drawKeyValue("Sales", value: ReportFormatting.currency(row.sales), indent: 16)
                    drawKeyValue("Expenses", value: ReportFormatting.currency(row.expenses), indent: 16)
                    if let overShort = row.overShort {
                        drawKeyValue("Over/Short", value: ReportFormatting.overShortLabel(overShort), indent: 16)
                    }
                    y += 8
                }
                y += sectionGap
            }
        }

        private func drawEmployeeBlockTitle(_ name: String) {
            beginPageIfNeeded(requiredHeight: 28)
            y = drawText(name, font: .boldSystemFont(ofSize: 13)) + 4
        }

        private func drawSubsectionTitle(_ title: String) {
            beginPageIfNeeded(requiredHeight: 18)
            y = drawText(title, font: .boldSystemFont(ofSize: 10), color: .darkGray) + 4
        }

        func drawEmptyNote(_ text: String) {
            beginPageIfNeeded(requiredHeight: lineHeight + 4)
            y = drawText(text, font: .italicSystemFont(ofSize: 11), color: .gray)
        }

        private func drawSectionTitle(_ title: String) {
            beginPageIfNeeded(requiredHeight: 22)
            y = drawText(title, font: .boldSystemFont(ofSize: 14)) + 8
        }

        private func estimatedLotteryRowHeight(_ row: LotteryReportRow) -> CGFloat {
            var lines: CGFloat = 4
            if row.actualEnclosed != nil { lines += 1 }
            if row.overShort != nil { lines += 1 }
            return lines * lineHeight + 14
        }

        private func drawFooter() {
            let text = "Oplix · Page \(pageNumber)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.gray
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: (pageWidth - size.width) / 2, y: pageHeight - margin),
                withAttributes: attrs
            )
        }

        private func drawKeyValue(_ key: String, value: String, indent: CGFloat = 0) {
            beginPageIfNeeded(requiredHeight: lineHeight)
            let x = margin + indent
            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.black
            ]
            (key as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: keyAttrs)
            (value as NSString).draw(at: CGPoint(x: x + 140, y: y), withAttributes: valAttrs)
            y += lineHeight
        }

        @discardableResult
        private func drawText(
            _ text: String,
            font: UIFont,
            color: UIColor = .black
        ) -> CGFloat {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let maxWidth = pageWidth - margin * 2
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            let textHeight = ceil(bounding.height)
            beginPageIfNeeded(requiredHeight: textHeight)

            let rect = CGRect(x: margin, y: y, width: maxWidth, height: textHeight)
            (text as NSString).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            y += textHeight
            return y
        }
    }

    private static func fileBaseName(for report: GeneratedReport) -> String {
        let safeLocation = report.locationName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: report.generatedAt)
        return "Oplix_\(report.type.displayName)_\(safeLocation)_\(stamp)"
    }
}
