//
//  LotteryShiftClosePackReplaceSheet.swift
//  Oplix
//

import SwiftUI

enum LotteryShiftClosePackReplaceScenario: String, CaseIterable, Identifiable {
    case soldFinished = "Sold out"
    // Returned packs are no longer handled here: a returned pack's bin
    // simply never gets scanned, so it surfaces in the incomplete-bins
    // check at close, where the employee can mark it returned.
    case returned = "Returned"

    var id: String { rawValue }
}

/// Prompt when shift-close scan finds a pack (or new game) that isn’t on the rack.
struct LotteryShiftClosePackReplacePrompt: Identifiable {
    /// Stable id so continuous rescans of the same pack don’t bounce the sheet.
    var id: String { "\(barcode.gameNumber)-\(barcode.packSerial)" }
    let barcode: OhioLotteryBarcode
    let candidates: [LotteryShiftCloseScanMatcher.RowContext]
    let reverseOrder: Bool
}

struct LotteryShiftClosePackReplaceSheet: View {
    let prompt: LotteryShiftClosePackReplacePrompt
    let onCancel: () -> Void
    /// scenario, selectedRowId, returnTicket, endingNumber, creditSealedBeginAsFullBook
    let onConfirm: (LotteryShiftClosePackReplaceScenario, String, String, String, Bool) async throws -> Void

    @State private var selectedRowId: String?
    @State private var creditSealedBeginAsFullBook = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedRow: LotteryShiftCloseScanMatcher.RowContext? {
        guard let selectedRowId else { return nil }
        return prompt.candidates.first { $0.id == selectedRowId }
    }

    private var endingFromScan: String {
        LotteryShiftCloseScanMatcher.normalizedTicketNumber(prompt.barcode.ticketNumber)
    }

    private var canConfirm: Bool {
        guard selectedRowId != nil, !isSaving else { return false }
        return !endingFromScan.isEmpty
    }

    private var scannedGameMatchesSelectedRow: Bool {
        guard let row = selectedRow else { return false }
        return OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, prompt.barcode.gameNumber)
    }

    private var oldPackBeginIsSealed: Bool {
        guard let row = selectedRow, !row.tickets.isEmpty else { return false }
        let sealed = LotteryCalculationService.sealedBeginTicket(
            ticketsInBook: row.tickets,
            reverseOrder: prompt.reverseOrder
        )
        return LotteryShiftCloseScanMatcher.ticketNumbersEqual(row.beginningNumber, sealed)
    }

    /// Old pack credit for the sold-out scenario: Begin → end of book.
    private var oldPackCreditLine: String? {
        guard let row = selectedRow else { return nil }
        if scannedGameMatchesSelectedRow {
            return nil
        }
        let (sold, _) = LotteryCalculationService.calculateFinishedPackSold(
            beginning: row.beginningNumber,
            ticketsInBook: row.tickets,
            reverseOrder: prompt.reverseOrder,
            creditFullBookIfSealedBegin: creditSealedBeginAsFullBook
        )
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        if sold == 0 {
            return "Old pack (Game \(row.gameNumber), Begin \(row.beginningNumber)): no sold-out credit — pack swapped only."
        }
        return "Old pack (Game \(row.gameNumber), Begin \(row.beginningNumber) → end of book): \(sold) tickets · $\(dollars) counted this shift."
    }

    /// Same-game: keep Begin → scanned End. Different game: sealed start → scan.
    private var newPackCountLine: String {
        let endLabel = endingFromScan.isEmpty ? "—" : endingFromScan

        if scannedGameMatchesSelectedRow, let row = selectedRow {
            let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: endingFromScan,
                tickets: row.tickets,
                reverseOrder: prompt.reverseOrder
            )
            let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
            let booksNote = books > 0 ? " (includes finished pack + new)" : ""
            return "Same game — continuous count: Begin \(row.beginningNumber) → \(endLabel) = \(sold) tickets · $\(dollars)\(booksNote). No separate sold-out credit."
        }
        return "New pack \(prompt.barcode.packSerial) (Game \(prompt.barcode.gameNumber)): counts from its sealed start → \(endLabel) this shift."
    }

    private var introCopy: String {
        if let row = selectedRow, scannedGameMatchesSelectedRow {
            return "Pack \(prompt.barcode.packSerial) is a new book of Game \(prompt.barcode.gameNumber). Same game on Bin #\(row.binNumber) — this shift keeps Begin \(row.beginningNumber) and sets End from the scan (no mid-shift sold-out credit)."
        }
        return "Pack \(prompt.barcode.packSerial) (Game \(prompt.barcode.gameNumber)) isn’t on the rack. Pick the bin it’s sitting on — if it’s a different game, the old pack will be credited as sold out (Begin → end of book)."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(introCopy)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Which bin is this pack on?") {
                    ForEach(prompt.candidates, id: \.id) { row in
                        Button {
                            selectedRowId = row.id
                            creditSealedBeginAsFullBook = false
                            errorMessage = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bin #\(row.binNumber)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Game \(row.gameNumber) · pack \(row.packSerial ?? "—") · Begin \(row.beginningNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !OhioLotteryBarcodeParser.gameNumbersMatch(
                                        row.gameNumber,
                                        prompt.barcode.gameNumber
                                    ) {
                                        Text("Different game — will become Game \(prompt.barcode.gameNumber)")
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
                        .buttonStyle(.plain)
                    }
                }

                if oldPackBeginIsSealed, !scannedGameMatchesSelectedRow {
                    Section("Old pack started sealed") {
                        Text("Begin is still at the sealed start, so the app can’t tell whether the whole pack sold out mid-shift or was just swapped. Default is no sold-out credit (avoids fake multi‑hundred dollars). Only turn this on if that pack truly sold out completely.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("Count entire old pack as sold", isOn: $creditSealedBeginAsFullBook)
                    }
                }

                Section("What will happen") {
                    if let oldPackCreditLine {
                        Text(oldPackCreditLine)
                            .font(.caption)
                            .foregroundColor(oldPackBeginIsSealed && creditSealedBeginAsFullBook ? .orange : .secondary)
                    }
                    Text(newPackCountLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !scannedGameMatchesSelectedRow {
                        Text("This assumes the new pack was sealed when it went on the bin. If it was already open (first-time setup or a transferred pack), cancel and assign it from Pack Inventory instead.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New pack on bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        Task { await confirm() }
                    }
                    .disabled(!canConfirm)
                }
            }
            .onAppear {
                if selectedRowId == nil {
                    if let sameGame = prompt.candidates.first(where: {
                        OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, prompt.barcode.gameNumber)
                    }) {
                        selectedRowId = sameGame.id
                    } else {
                        selectedRowId = prompt.candidates.first?.id
                    }
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Saving…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
        }
    }

    private func confirm() async {
        guard let selectedRowId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onConfirm(
                .soldFinished,
                selectedRowId,
                "",
                endingFromScan,
                creditSealedBeginAsFullBook
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
