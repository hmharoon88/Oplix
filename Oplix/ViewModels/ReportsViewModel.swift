//
//  ReportsViewModel.swift
//  Oplix
//

import Foundation

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var selectedLocationId: String?
    @Published var selectedType: ReportType = .lottery
    @Published var selectedPreset: ReportPeriodPreset = .monthToDate
    @Published var customStartDate = Calendar.current.startOfDay(for: Date())
    @Published var customEndDate = Date()

    @Published var isLoadingLocations = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var generatedReport: GeneratedReport?
    @Published var pdfURL: URL?

    private let firebaseService = FirebaseService.shared
    private let userId: String
    private let organizationName: String?

    init(userId: String, organizationName: String?) {
        self.userId = userId
        self.organizationName = organizationName
    }

    var selectedLocation: Location? {
        guard let id = selectedLocationId else { return nil }
        return locations.first { $0.id == id }
    }

    func loadLocations() async {
        isLoadingLocations = true
        errorMessage = nil
        defer { isLoadingLocations = false }

        do {
            let list = try await firebaseService.fetchLocations(userId: userId)
            locations = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if selectedLocationId == nil {
                selectedLocationId = locations.first?.id
            } else if !locations.contains(where: { $0.id == selectedLocationId }) {
                selectedLocationId = locations.first?.id
            }
        } catch {
            errorMessage = "Failed to load locations: \(error.localizedDescription)"
        }
    }

    func generateReport() async {
        guard let location = selectedLocation else {
            errorMessage = "Select a location."
            return
        }

        let interval = ReportDateRange.interval(
            preset: selectedPreset,
            customStart: customStartDate,
            customEnd: customEndDate
        )

        guard interval.isValid else {
            errorMessage = "End date must be on or after start date."
            return
        }

        if ReportDateRange.spanExceedsLimit(interval) {
            errorMessage = "Date range cannot exceed \(ReportDateInterval.maxSpanDays) days."
            return
        }

        isGenerating = true
        errorMessage = nil
        generatedReport = nil
        pdfURL = nil
        defer { isGenerating = false }

        do {
            let reportType = selectedType
            async let shiftsTask = firebaseService.fetchShifts(userId: userId, locationId: location.id)
            async let employeesTask = firebaseService.fetchEmployees(userId: userId, locationId: location.id)
            async let lotteryTask = firebaseService.fetchLotteryForms(userId: userId, locationId: location.id)
            async let booksTask: [BooksMonthPayload] = {
                guard reportType == .register else { return [] }
                return (try? await BooksService.shared.loadAllMonths(
                    userId: userId,
                    locationId: location.id
                )) ?? []
            }()

            let shifts = try await shiftsTask
            let employees = try await employeesTask
            let lotteryForms = try await lotteryTask
            let booksPayloads = await booksTask

            let report = buildGeneratedReport(
                type: reportType,
                locationName: location.name,
                interval: interval,
                shifts: shifts,
                employees: employees,
                lotteryForms: lotteryForms,
                booksPayloads: booksPayloads,
                hasGasStation: location.hasGasStation
            )

            generatedReport = report
            pdfURL = try ReportPDFRenderer.renderPDF(report: report)
        } catch {
            errorMessage = "Failed to generate report: \(error.localizedDescription)"
        }
    }

    func clearGenerated() {
        generatedReport = nil
        pdfURL = nil
    }

    private func buildGeneratedReport(
        type: ReportType,
        locationName: String,
        interval: ReportDateInterval,
        shifts: [Shift],
        employees: [Employee],
        lotteryForms: [LotteryForm],
        booksPayloads: [BooksMonthPayload] = [],
        hasGasStation: Bool = false
    ) -> GeneratedReport {
        var lottery: LotteryReportContent?
        var payroll: PayrollReportContent?
        var register: RegisterReportContent?

        switch type {
        case .lottery:
            lottery = ReportDataBuilder.buildLotteryReport(
                forms: lotteryForms,
                shifts: shifts,
                employees: employees,
                interval: interval
            )
        case .payroll:
            payroll = ReportDataBuilder.buildPayrollReport(
                shifts: shifts,
                employees: employees,
                interval: interval
            )
        case .register:
            let shiftReport = ReportDataBuilder.buildRegisterReport(
                shifts: shifts,
                employees: employees,
                interval: interval
            )
            let booksReport = ReportDataBuilder.buildRegisterReportFromBooks(
                payloads: booksPayloads,
                interval: interval,
                hasGasStation: hasGasStation
            )
            register = ReportDataBuilder.mergeRegisterReports(books: booksReport, shifts: shiftReport)
        }

        let briefSummary = ReportBriefSummaryBuilder.build(
            type: type,
            lottery: lottery,
            payroll: payroll,
            register: register
        )

        return GeneratedReport(
            type: type,
            locationName: locationName,
            organizationName: organizationName,
            interval: interval,
            generatedAt: Date(),
            briefSummary: briefSummary,
            lottery: lottery,
            payroll: payroll,
            register: register
        )
    }
}
