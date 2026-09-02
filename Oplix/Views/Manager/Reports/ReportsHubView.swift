//
//  ReportsHubView.swift
//  Oplix
//

import SwiftUI

struct ReportsHubView: View {
    @StateObject private var viewModel: ReportsViewModel
    @State private var showingShare = false

    init(userId: String, organizationName: String?, preselectedLocationId: String? = nil) {
        let vm = ReportsViewModel(userId: userId, organizationName: organizationName)
        if let preselectedLocationId {
            vm.selectedLocationId = preselectedLocationId
        }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            Form {
                locationSection
                reportTypeSection
                periodSection
                generateSection

                if let report = viewModel.generatedReport {
                    previewSection(report: report)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadLocations()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showingShare) {
            if let url = viewModel.pdfURL {
                ReportShareSheet(items: [url])
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if viewModel.isLoadingLocations {
                HStack {
                    ProgressView()
                    Text("Loading locations…")
                        .foregroundColor(.secondary)
                }
            } else if viewModel.locations.isEmpty {
                Text("No locations found. Add a facility on the Oplix web dashboard first.")
                    .foregroundColor(.secondary)
            } else {
                Picker("Location", selection: Binding(
                    get: { viewModel.selectedLocationId ?? "" },
                    set: { newValue in
                        viewModel.selectedLocationId = newValue.isEmpty ? nil : newValue
                        viewModel.clearGenerated()
                    }
                )) {
                    ForEach(viewModel.locations) { location in
                        Text(location.name).tag(location.id)
                    }
                }
            }
        }
    }

    private var reportTypeSection: some View {
        Section("Report type") {
            Picker("Type", selection: Binding(
                get: { viewModel.selectedType },
                set: { newValue in
                    viewModel.selectedType = newValue
                    viewModel.clearGenerated()
                }
            )) {
                ForEach(ReportType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImage)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)

            Text(reportTypeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var reportTypeDescription: String {
        switch viewModel.selectedType {
        case .lottery:
            return "Sales, expected and actual cash enclosed, and over/short for each lottery close."
        case .payroll:
            return "Hours and pay by employee for completed shifts at this location."
        case .register:
            return "Daily sales and expenses from Daily books (web). Shift register data is included when employees enter it on shifts."
        }
    }

    private var periodSection: some View {
        Section("Date range") {
            Picker("Period", selection: Binding(
                get: { viewModel.selectedPreset },
                set: { newValue in
                    viewModel.selectedPreset = newValue
                    viewModel.clearGenerated()
                }
            )) {
                ForEach(ReportPeriodPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)

            if viewModel.selectedPreset == .custom {
                DatePicker(
                    "Start",
                    selection: $viewModel.customStartDate,
                    displayedComponents: .date
                )
                .onChange(of: viewModel.customStartDate) { _, _ in viewModel.clearGenerated() }

                DatePicker(
                    "End",
                    selection: $viewModel.customEndDate,
                    in: viewModel.customStartDate...,
                    displayedComponents: .date
                )
                .onChange(of: viewModel.customEndDate) { _, _ in viewModel.clearGenerated() }
            } else {
                let interval = ReportDateRange.interval(
                    preset: viewModel.selectedPreset,
                    customStart: viewModel.customStartDate,
                    customEnd: viewModel.customEndDate
                )
                Text(ReportDateRange.formattedRange(interval))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var generateSection: some View {
        Section {
            Button {
                Task { await viewModel.generateReport() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isGenerating {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Generating…")
                    } else {
                        Image(systemName: "doc.text.fill")
                        Text("Generate report")
                    }
                    Spacer()
                }
            }
            .disabled(
                viewModel.isGenerating
                || viewModel.selectedLocationId == nil
                || viewModel.locations.isEmpty
            )
        } footer: {
            Text("Reports are generated on this device as a PDF. Maximum range: \(ReportDateInterval.maxSpanDays) days. Manager access only.")
        }
    }

    @ViewBuilder
    private func previewSection(report: GeneratedReport) -> some View {
        Section {
            ReportGeneratedPreview(report: report)
        } header: {
            Text("Report preview")
        } footer: {
            if viewModel.pdfURL != nil {
                Text("Full detail is included in the PDF. Expand each employee to preview line items.")
            }
        }

        if viewModel.pdfURL != nil {
            Section {
                Button {
                    showingShare = true
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
