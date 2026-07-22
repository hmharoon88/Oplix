//
//  AssignStockPackSheet.swift
//  Oplix
//
//  Place an in-stock pack onto a rack bin.
//

import SwiftUI

struct AssignStockPackSheet: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    let pack: LotteryStockPack
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRowId: String?
    @State private var showingReplaceConfirm = false
    @State private var localError: String?

    private var binRows: [LotteryPackRackRow] {
        viewModel.allBinRows()
    }

    private var selectedRow: LotteryPackRackRow? {
        guard let selectedRowId else { return nil }
        return binRows.first { $0.id == selectedRowId }
    }

    private var syntheticBarcode: OhioLotteryBarcode {
        let ticket = pack.receivedTicketNumber.isEmpty ? "00" : pack.receivedTicketNumber
        let position = ticket == "00" || ticket == "0" ? "000" : {
            if let n = Int(ticket) { return String(format: "%03d", n) }
            return ticket
        }()
        return OhioLotteryBarcode(
            raw: "\(pack.gameNumber)-\(pack.packSerial)-\(position)-0",
            gameNumber: pack.gameNumber,
            packSerial: pack.packSerial,
            ticketPosition: position,
            ticketNumber: LotteryShiftCloseScanMatcher.normalizedTicketNumber(ticket),
            checkDigit: "0",
            bookDigits: "\(pack.gameNumber)\(pack.packSerial)\(position)0".filter(\.isNumber)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stock pack") {
                    LabeledContent("Game", value: pack.gameNumber)
                    LabeledContent("Pack", value: pack.packSerial)
                    LabeledContent("Value", value: "$\(pack.value)")
                    LabeledContent("Tickets", value: pack.tickets)
                }

                Section("Assign to bin") {
                    ForEach(binRows) { row in
                        Button {
                            selectedRowId = row.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Bin \(row.binNumber)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if row.hasActivePack {
                                        Text("Game \(row.gameNumber) · pack \(row.packSerial ?? "—")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, pack.gameNumber) {
                                            Text("Same game — keeps Begin \(row.beginningNumber)")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("Different game — old pack credited sold out")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    } else {
                                        Text("Empty")
                                            .font(.caption)
                                            .foregroundColor(.green)
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

                if let localError {
                    Section {
                        Text(localError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Assign from stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        attemptAssign()
                    }
                    .disabled(selectedRowId == nil || viewModel.isSaving)
                }
            }
            .confirmationDialog(
                "Bin already has a pack",
                isPresented: $showingReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Replace pack on this bin", role: .destructive) {
                    Task { await confirmAssign() }
                }
            } message: {
                if let row = selectedRow {
                    Text(viewModel.replaceConfirmationMessage(row: row, barcode: syntheticBarcode))
                }
            }
        }
    }

    private func attemptAssign() {
        guard let row = selectedRow else { return }
        if viewModel.requiresReplaceConfirmation(row: row, barcode: syntheticBarcode) {
            showingReplaceConfirm = true
        } else {
            Task { await confirmAssign() }
        }
    }

    private func confirmAssign() async {
        guard let rowId = selectedRowId else { return }
        localError = nil
        do {
            try await viewModel.assignStockPack(pack, toRowId: rowId)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
