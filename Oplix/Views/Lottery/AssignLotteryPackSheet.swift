//
//  AssignLotteryPackSheet.swift
//  Oplix
//

import SwiftUI

struct AssignLotteryPackSheet: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var barcodeText = ""
    @State private var parsedBarcode: OhioLotteryBarcode?
    @State private var binRows: [LotteryPackRackRow] = []
    @State private var currentPackBin: LotteryPackRackRow?
    @State private var selectedRowId: String?
    @State private var showingScanner = false
    @State private var showingReplaceConfirm = false
    @State private var showingOpenPackConfirm = false
    @State private var localError: String?

    @State private var newGameValue = ""
    @State private var newGameTickets = ""
    @State private var confirmOpenPackForNewGame = false
    @State private var showingTenDollarConfirm = false
    @State private var confirmedTenDollarTickets = false

    private var isNewGame: Bool {
        guard let parsedBarcode else { return false }
        return !viewModel.isKnownGame(parsedBarcode.gameNumber)
    }

    private var normalizedNewGameValue: String {
        LotteryGameTicketDefaults.normalizeValue(newGameValue)
    }

    private var suggestedNewGameTickets: String? {
        viewModel.suggestedTickets(forNewGameValue: newGameValue)
    }

    private var needsTenDollarConfirm: Bool {
        isNewGame && LotteryGameTicketDefaults.requiresTicketConfirmation(value: newGameValue)
    }

    private var selectedRow: LotteryPackRackRow? {
        guard let selectedRowId else { return nil }
        return binRows.first(where: { $0.id == selectedRowId })
    }

    private var canConfirmAssign: Bool {
        guard selectedRowId != nil, parsedBarcode != nil, !viewModel.isSaving else { return false }
        if isNewGame {
            guard !normalizedNewGameValue.isEmpty else { return false }
            let tickets = resolvedNewGameTickets
            guard !tickets.isEmpty else { return false }
            if let parsed = parsedBarcode, !parsed.isSealedPack, !confirmOpenPackForNewGame {
                return false
            }
        }
        return true
    }

    /// Tickets that will be written with the new game (suggestion, or manual when unknown / $10 override).
    private var resolvedNewGameTickets: String {
        let typed = LotteryGameTicketDefaults.normalizeTickets(newGameTickets) ?? ""
        if !typed.isEmpty { return typed }
        return suggestedNewGameTickets ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pack barcode") {
                    HStack {
                        TextField("1091-0017360-000-2", text: $barcodeText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: barcodeText) { _, _ in
                                parseBarcodeInput()
                            }

                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title3)
                        }
                        .accessibilityLabel("Scan barcode")
                    }

                    if let parsed = parsedBarcode {
                        LabeledContent("Book #", value: parsed.dashedLabel)
                        LabeledContent("Game", value: parsed.gameNumber)
                        LabeledContent("Pack serial", value: parsed.packSerial)
                        LabeledContent("Top ticket #", value: parsed.ticketNumber)
                        if parsed.extraScannerDigitCount > 0 {
                            Text("Scanner added \(parsed.extraScannerDigitCount) extra digits after the book number — those are ignored.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if parsed.isSealedPack {
                            Text("Sealed pack — ticket position 000 on barcode.")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text(openPackInlineWarning(for: parsed))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if let currentPackBin {
                            Text("This pack is on Bin \(currentPackBin.binNumber). Choose any bin to move or reassign it.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                if isNewGame, let parsed = parsedBarcode {
                    Section("New game") {
                        Text("Game \(parsed.gameNumber) isn't in your game database yet. Enter the ticket value — tickets per pack are filled from your other games when possible.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Value per ticket (e.g. 5)", text: $newGameValue)
                            .keyboardType(.decimalPad)
                            .onChange(of: newGameValue) { _, _ in
                                confirmedTenDollarTickets = false
                                applySuggestedTicketsIfNeeded()
                            }

                        if let suggested = suggestedNewGameTickets {
                            LabeledContent("Tickets per pack", value: resolvedNewGameTickets)
                            Text(
                                LotteryGameTicketDefaults.suggestionCaption(
                                    value: newGameValue,
                                    tickets: suggested,
                                    fromCatalog: viewModel.newGameSuggestionUsesCatalog(value: newGameValue)
                                )
                            )
                            .font(.caption)
                            .foregroundColor(needsTenDollarConfirm ? .orange : .secondary)

                            if needsTenDollarConfirm {
                                TextField("Tickets per pack (confirm / edit)", text: $newGameTickets)
                                    .keyboardType(.numberPad)
                            }
                        } else if !normalizedNewGameValue.isEmpty {
                            TextField("Tickets per pack", text: $newGameTickets)
                                .keyboardType(.numberPad)
                            Text("No matching games for $\(normalizedNewGameValue) yet — enter tickets per pack.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        if parsed.isSealedPack {
                            Label("Barcode shows a sealed pack (Begin 00). Good for a new game.", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("This barcode shows ticket #\(parsed.ticketNumber), not 00. Brand-new packs are usually sealed (000 on the barcode). You may have the wrong barcode.")
                                .font(.caption)
                                .foregroundColor(.orange)

                            Toggle("This pack is already open — add anyway", isOn: $confirmOpenPackForNewGame)
                                .font(.subheadline)
                        }
                    }
                }

                if let parsed = parsedBarcode, !binRows.isEmpty {
                    assignmentSuggestions(for: parsed)

                    Section {
                        ForEach(binRows) { row in
                            Button {
                                selectedRowId = row.id
                            } label: {
                                binRowLabel(row: row, parsed: parsed)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(currentPackBin == nil ? "Assign to any bin" : "Move to any bin")
                    } footer: {
                        Text("Multiple bins can hold the same game # — each pack is tracked by pack serial. Assign puts the pack on the bin without changing Begin/End. Different-game replace still credits the old pack as finished (Begin→00) at the next shift close.")
                    }
                }

                if let parsed = parsedBarcode, let row = selectedRow {
                    switch viewModel.assignSituation(row: row, barcode: parsed) {
                    case .replaceSameGame, .replaceDifferentGame:
                        Section {
                            Text(viewModel.replaceConfirmationMessage(row: row, barcode: parsed))
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        } header: {
                            Label("This bin already has a pack", systemImage: "exclamationmark.triangle.fill")
                        }
                    case .empty, .currentLocation:
                        EmptyView()
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
            .navigationTitle(currentPackBin == nil ? "Assign pack" : "Move pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        attemptConfirmAssign()
                    }
                    .disabled(!canConfirmAssign)
                }
            }
            .sheet(isPresented: $showingScanner) {
                LotteryBarcodeScannerSheet(knownGameNumbers: viewModel.knownGameNumbers) { value in
                    showingScanner = false
                    barcodeText = value
                    parseBarcodeInput()
                    if let parsed = parsedBarcode {
                        LotteryScanFeedback.speakTicket(parsed.ticketNumber, game: parsed.gameNumber)
                    }
                }
            }
            .confirmationDialog(
                "Bin already has a pack",
                isPresented: $showingReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Replace pack on this bin", role: .destructive) {
                    continueAfterReplaceDecision()
                }
            } message: {
                if let parsed = parsedBarcode, let row = selectedRow {
                    Text(viewModel.replaceConfirmationMessage(row: row, barcode: parsed))
                } else {
                    Text("This bin already has a pack on the rack. Replacing it will credit the old pack as finished (sold) at the next shift close.")
                }
            }
            .confirmationDialog(
                "Open pack — not sealed",
                isPresented: $showingOpenPackConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Assign anyway", role: .destructive) {
                    Task { await confirmAssign() }
                }
            } message: {
                if let parsed = parsedBarcode {
                    Text(viewModel.openPackConfirmationMessage(
                        barcode: parsed,
                        ticketsInBookOverride: isNewGame ? resolvedNewGameTickets : nil
                    ))
                }
            }
            .confirmationDialog(
                "Confirm $10 game",
                isPresented: $showingTenDollarConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Add with \(resolvedNewGameTickets) tickets") {
                    confirmedTenDollarTickets = true
                    continueAfterTenDollarDecision()
                }
            } message: {
                Text("Most $10 packs have 50 tickets; a few have 30. This game will be saved with \(resolvedNewGameTickets) tickets per pack.")
            }
        }
    }

    @ViewBuilder
    private func assignmentSuggestions(for parsed: OhioLotteryBarcode) -> some View {
        let emptyBins = viewModel.suggestedEmptyBins(for: parsed)
        let sameGameBins = viewModel.binsWithSameGame(as: parsed)

        if !emptyBins.isEmpty || !sameGameBins.isEmpty {
            Section("Suggestions") {
                if !emptyBins.isEmpty {
                    Label {
                        Text("Empty bins: \(emptyBins.map(\.binNumber).joined(separator: ", "))")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "tray")
                            .foregroundColor(.green)
                    }
                }
                if !sameGameBins.isEmpty {
                    Label {
                        Text("Game \(parsed.gameNumber) is already on bin(s) \(sameGameBins.map(\.binNumber).joined(separator: ", ")) with other pack serials — you can add this pack to a different empty bin.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func binRowLabel(row: LotteryPackRackRow, parsed: OhioLotteryBarcode) -> some View {
        let situation = viewModel.assignSituation(row: row, barcode: parsed)

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bin \(row.binNumber)")
                    .font(.headline)

                switch situation {
                case .currentLocation:
                    Text("Current location")
                        .font(.caption)
                        .foregroundColor(.green)
                case .empty:
                    Text("Empty — ready for this pack")
                        .font(.caption)
                        .foregroundColor(.green)
                case .replaceSameGame(let existingSerial):
                    Text("Game \(row.gameNumber) · pack \(existingSerial)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Finished pack — will credit sold, then assign new")
                        .font(.caption2)
                        .foregroundColor(.orange)
                case .replaceDifferentGame(let existingGame, let existingSerial):
                    Text("Has Game \(existingGame) · pack \(existingSerial)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Finished pack — will credit sold, then assign new")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            if selectedRowId == row.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private var confirmButtonTitle: String {
        if isNewGame { return "Add game & assign" }
        return currentPackBin == nil ? "Assign" : "Move"
    }

    private func parseBarcodeInput() {
        localError = nil
        let trimmed = barcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetParsedState()
            return
        }

        switch OhioLotteryBarcodeParser.parse(trimmed) {
        case .success(let barcode):
            parsedBarcode = barcode
            currentPackBin = viewModel.rowHoldingPack(serial: barcode.packSerial)
            binRows = viewModel.sortedBinRows(for: barcode)
            if !viewModel.isKnownGame(barcode.gameNumber) {
                newGameValue = ""
                newGameTickets = ""
                confirmOpenPackForNewGame = false
                confirmedTenDollarTickets = false
            }
            if let current = currentPackBin {
                selectedRowId = current.id
            } else if let firstEmpty = viewModel.suggestedEmptyBins(for: barcode).first {
                // New pack — always suggest an empty bin, even if user had another bin selected earlier.
                selectedRowId = firstEmpty.id
            } else if let selected = selectedRowId,
                      !binRows.contains(where: { $0.id == selected }) {
                selectedRowId = binRows.first?.id
            } else if selectedRowId == nil {
                selectedRowId = binRows.first?.id
            }
            if binRows.isEmpty {
                localError = "No bin row on this terminal. Add rows in lottery customization first."
            }
        case .failure(let error):
            resetParsedState()
            switch error {
            case .empty: localError = nil
            case .invalidFormat: localError = "Invalid barcode format."
            case .notLotteryBarcode: localError = "Not a lottery pack barcode."
            }
        }
    }

    private func resetParsedState() {
        parsedBarcode = nil
        binRows = []
        currentPackBin = nil
        selectedRowId = nil
        newGameValue = ""
        newGameTickets = ""
        confirmOpenPackForNewGame = false
        confirmedTenDollarTickets = false
    }

    private func applySuggestedTicketsIfNeeded() {
        guard let suggested = suggestedNewGameTickets else { return }
        if needsTenDollarConfirm {
            // Prefill once; allow the user to edit before confirming.
            if newGameTickets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newGameTickets = suggested
            }
        } else {
            newGameTickets = suggested
        }
    }

    private func openPackInlineWarning(for parsed: OhioLotteryBarcode) -> String {
        guard let preview = viewModel.openPackAlreadySoldPreview(
            barcode: parsed,
            ticketsInBookOverride: isNewGame ? resolvedNewGameTickets : nil
        ) else {
            return "Open pack — top ticket #\(parsed.ticketNumber). Assign will not change Begin/End on the bin."
        }
        if preview.alreadySold > 0 {
            return "Open pack at #\(preview.ticketNumber) — about \(preview.alreadySold) tickets already sold from sealed. Assign does not change Begin/End; make sure the bin's Begin is correct."
        }
        return "Open pack — barcode ticket #\(parsed.ticketNumber). Assign does not change Begin/End on the bin."
    }

    private func attemptConfirmAssign() {
        guard let parsed = parsedBarcode, let row = selectedRow else { return }
        if viewModel.requiresReplaceConfirmation(row: row, barcode: parsed) {
            showingReplaceConfirm = true
        } else {
            continueAfterReplaceDecision()
        }
    }

    private func continueAfterReplaceDecision() {
        if isNewGame, needsTenDollarConfirm, !confirmedTenDollarTickets {
            if newGameTickets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggested = suggestedNewGameTickets {
                newGameTickets = suggested
            }
            showingTenDollarConfirm = true
            return
        }
        continueAfterTenDollarDecision()
    }

    private func continueAfterTenDollarDecision() {
        guard let parsed = parsedBarcode else { return }
        if viewModel.requiresOpenPackConfirmation(barcode: parsed) {
            showingOpenPackConfirm = true
        } else {
            Task { await confirmAssign() }
        }
    }

    private func confirmAssign() async {
        guard let rowId = selectedRowId else { return }
        localError = nil
        do {
            if isNewGame {
                let value = normalizedNewGameValue
                let tickets = resolvedNewGameTickets
                try await viewModel.assignPack(
                    barcodeRaw: barcodeText,
                    toRowId: rowId,
                    newGameValue: value,
                    newGameTickets: tickets,
                    confirmOpenPackForNewGame: confirmOpenPackForNewGame
                )
            } else {
                try await viewModel.assignPack(barcodeRaw: barcodeText, toRowId: rowId)
            }
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
