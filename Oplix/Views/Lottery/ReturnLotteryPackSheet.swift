//
//  ReturnLotteryPackSheet.swift
//  Oplix
//

import SwiftUI

private enum ReturnEntryMode: String, CaseIterable, Identifiable {
    case scan = "Scan barcode"
    case manual = "From rack"

    var id: String { rawValue }
}

struct ReturnLotteryPackSheet: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryMode: ReturnEntryMode = .scan
    @State private var barcodeText = ""
    @State private var parsedBarcode: OhioLotteryBarcode?
    @State private var matchedRow: LotteryPackRackRow?
    @State private var selectedRowId: String?
    @State private var manualTicketText = ""
    @State private var showingScanner = false
    @State private var localError: String?
    @State private var previewTickets = 0
    @State private var previewDollars: Double = 0

    private var canConfirm: Bool {
        switch entryMode {
        case .scan:
            return matchedRow != nil && parsedBarcode != nil
        case .manual:
            return selectedRowId != nil && !manualTicketText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $entryMode) {
                        ForEach(ReturnEntryMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: entryMode) { _, _ in
                        resetPreview()
                    }
                }

                switch entryMode {
                case .scan:
                    scanSection
                case .manual:
                    manualSection
                }

                if previewTickets > 0 || previewDollars > 0 {
                    Section("Return preview") {
                        LabeledContent("Return tickets", value: "\(previewTickets)")
                        LabeledContent("Return dollars", value: formatCurrency(previewDollars))
                    }
                }

                if let localError {
                    Section {
                        Text(localError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Return pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Return") {
                        Task { await confirmReturn() }
                    }
                    .disabled(!canConfirm || viewModel.isSaving)
                }
            }
            .sheet(isPresented: $showingScanner) {
                LotteryBarcodeScannerSheet(knownGameNumbers: viewModel.knownGameNumbers) { value in
                    showingScanner = false
                    barcodeText = value
                    parseScanInput()
                    if let parsed = parsedBarcode {
                        LotteryScanFeedback.speakTicket(parsed.ticketNumber, game: parsed.gameNumber)
                    }
                }
            }
        }
    }

    private var scanSection: some View {
        Group {
            Section("Scan returned pack") {
                HStack {
                    TextField("1091-0017360-014-2", text: $barcodeText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: barcodeText) { _, _ in
                            parseScanInput()
                        }

                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title3)
                    }
                }

                Text("Scan the pack barcode with the current top ticket showing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let row = matchedRow, let parsed = parsedBarcode {
                Section("Matched bin") {
                    LabeledContent("Bin", value: row.binNumber)
                    LabeledContent("Book #", value: parsed.dashedLabel)
                    LabeledContent("Game", value: row.gameNumber)
                    LabeledContent("Pack", value: parsed.packSerial)
                    LabeledContent("Ticket", value: parsed.ticketNumber)
                    if parsed.extraScannerDigitCount > 0 {
                        Text("Scanner added \(parsed.extraScannerDigitCount) extra digits after the book number — ignored.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var manualSection: some View {
        Group {
            Section {
                Text("Use when the pack is already gone but this terminal still shows it on the rack.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.activePackRows.isEmpty {
                Section {
                    Text("No active packs on this terminal.")
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Select pack on rack") {
                    ForEach(viewModel.activePackRows) { row in
                        Button {
                            selectedRowId = row.id
                            updateManualPreview()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bin \(row.binNumber)")
                                        .font(.headline)
                                    Text("Game \(row.gameNumber) · Pack \(row.packSerial ?? "—")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !row.beginningNumber.isEmpty {
                                        Text("Begin # \(row.beginningNumber)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedRowId == row.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Top ticket when returned") {
                    TextField("e.g. 14 or 00 for full book", text: $manualTicketText)
                        .keyboardType(.numberPad)
                        .onChange(of: manualTicketText) { _, _ in
                            updateManualPreview()
                        }

                    Text("Enter the ticket # showing on the pack when it was sent back to Ohio Lottery. Use 00 if the whole sealed book was returned.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func resetPreview() {
        localError = nil
        previewTickets = 0
        previewDollars = 0
        if entryMode == .scan {
            selectedRowId = nil
            manualTicketText = ""
        } else {
            barcodeText = ""
            parsedBarcode = nil
            matchedRow = nil
        }
    }

    private func parseScanInput() {
        localError = nil
        let trimmed = barcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsedBarcode = nil
            matchedRow = nil
            previewTickets = 0
            previewDollars = 0
            return
        }

        switch OhioLotteryBarcodeParser.parse(trimmed) {
        case .success(let barcode):
            parsedBarcode = barcode
            if let row = viewModel.matchedRow(for: barcode) {
                matchedRow = row
                if let preview = viewModel.returnPreview(rowId: row.id, fromTicket: barcode.ticketNumber) {
                    previewTickets = preview.tickets
                    previewDollars = preview.dollars
                }
            } else {
                matchedRow = nil
                previewTickets = 0
                previewDollars = 0
                localError = "No active pack with serial \(barcode.packSerial) on this terminal."
            }
        case .failure(let error):
            parsedBarcode = nil
            matchedRow = nil
            previewTickets = 0
            previewDollars = 0
            switch error {
            case .empty: localError = nil
            case .invalidFormat: localError = "Invalid barcode format."
            case .notLotteryBarcode: localError = "Not a lottery pack barcode."
            }
        }
    }

    private func updateManualPreview() {
        localError = nil
        guard let rowId = selectedRowId else {
            previewTickets = 0
            previewDollars = 0
            return
        }
        let ticket = manualTicketText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticket.isEmpty else {
            previewTickets = 0
            previewDollars = 0
            return
        }
        if let preview = viewModel.returnPreview(rowId: rowId, fromTicket: ticket) {
            previewTickets = preview.tickets
            previewDollars = preview.dollars
        } else {
            previewTickets = 0
            previewDollars = 0
            localError = "Couldn't calculate return for that bin."
        }
    }

    private func confirmReturn() async {
        localError = nil
        do {
            switch entryMode {
            case .scan:
                try await viewModel.returnPack(barcodeRaw: barcodeText)
            case .manual:
                guard let rowId = selectedRowId else { return }
                try await viewModel.returnPackManually(rowId: rowId, fromTicket: manualTicketText)
            }
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
