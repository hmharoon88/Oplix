//
//  ReceiveLotteryPackSheet.swift
//  Oplix
//
//  Receive a pack into location stock (not on a bin).
//

import SwiftUI

struct ReceiveLotteryPackSheet: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var barcodeText = ""
    @State private var parsedBarcode: OhioLotteryBarcode?
    @State private var showingScanner = false
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

    private var resolvedNewGameTickets: String {
        let typed = LotteryGameTicketDefaults.normalizeTickets(newGameTickets) ?? ""
        if !typed.isEmpty { return typed }
        return suggestedNewGameTickets ?? ""
    }

    private var canConfirm: Bool {
        guard parsedBarcode != nil, !viewModel.isSaving else { return false }
        if isNewGame {
            guard !normalizedNewGameValue.isEmpty else { return false }
            guard !resolvedNewGameTickets.isEmpty else { return false }
            if let parsed = parsedBarcode, !parsed.isSealedPack, !confirmOpenPackForNewGame {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scan or enter a pack barcode to put it in stock. Assign it to a bin later, or scan it at shift close.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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
                        if parsed.isSealedPack {
                            Text("Sealed pack — ready for stock.")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Open pack at ticket #\(parsed.ticketNumber). Prefer receiving sealed packs when possible.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                if isNewGame, let parsed = parsedBarcode {
                    Section("New game") {
                        Text("Game \(parsed.gameNumber) isn’t in your database yet. Enter the ticket value.")
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
                        }

                        if !parsed.isSealedPack {
                            Toggle("This pack is already open — receive anyway", isOn: $confirmOpenPackForNewGame)
                        }
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
            .navigationTitle("Receive into stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Receive") {
                        attemptReceive()
                    }
                    .disabled(!canConfirm)
                }
            }
            .sheet(isPresented: $showingScanner) {
                LotteryBarcodeScannerSheet(knownGameNumbers: viewModel.knownGameNumbers) { value in
                    showingScanner = false
                    barcodeText = value
                    parseBarcodeInput()
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
                    Task { await confirmReceive() }
                }
            } message: {
                Text("Most $10 packs have 50 tickets; a few have 30. This game will be saved with \(resolvedNewGameTickets) tickets per pack.")
            }
        }
    }

    private func parseBarcodeInput() {
        localError = nil
        let trimmed = barcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsedBarcode = nil
            return
        }

        switch OhioLotteryBarcodeParser.parse(trimmed) {
        case .success(let barcode):
            parsedBarcode = barcode
            if !viewModel.isKnownGame(barcode.gameNumber) {
                newGameValue = ""
                newGameTickets = ""
                confirmOpenPackForNewGame = false
                confirmedTenDollarTickets = false
            }
        case .failure(let error):
            parsedBarcode = nil
            switch error {
            case .empty: localError = nil
            case .invalidFormat: localError = "Invalid barcode format."
            case .notLotteryBarcode: localError = "Not a lottery pack barcode."
            }
        }
    }

    private func applySuggestedTicketsIfNeeded() {
        guard let suggested = suggestedNewGameTickets else { return }
        if needsTenDollarConfirm {
            if newGameTickets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newGameTickets = suggested
            }
        } else {
            newGameTickets = suggested
        }
    }

    private func attemptReceive() {
        if isNewGame, needsTenDollarConfirm, !confirmedTenDollarTickets {
            if newGameTickets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggested = suggestedNewGameTickets {
                newGameTickets = suggested
            }
            showingTenDollarConfirm = true
            return
        }
        Task { await confirmReceive() }
    }

    private func confirmReceive() async {
        localError = nil
        do {
            if isNewGame {
                try await viewModel.receiveStockPack(
                    barcodeRaw: barcodeText,
                    newGameValue: normalizedNewGameValue,
                    newGameTickets: resolvedNewGameTickets,
                    confirmOpenPackForNewGame: confirmOpenPackForNewGame
                )
            } else {
                try await viewModel.receiveStockPack(barcodeRaw: barcodeText)
            }
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
