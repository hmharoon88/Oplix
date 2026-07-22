//
//  MoveLotteryPackSheet.swift
//  Oplix
//

import SwiftUI

/// Reassign an active pack to an empty bin without sales, returns, or closeouts.
struct MoveLotteryPackSheet: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fromRowId: String?
    @State private var toRowId: String?
    @State private var localError: String?

    private var sourceRows: [LotteryPackRackRow] {
        viewModel.activePackRows
    }

    private var destinationRows: [LotteryPackRackRow] {
        viewModel.emptyBinRows.filter { $0.id != fromRowId }
    }

    private var selectedSource: LotteryPackRackRow? {
        guard let fromRowId else { return nil }
        return sourceRows.first(where: { $0.id == fromRowId })
    }

    private var canConfirm: Bool {
        fromRowId != nil && toRowId != nil && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Moves a pack to another bin only. Does not add sales or create a return.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("From bin (active pack)") {
                    if sourceRows.isEmpty {
                        Text("No active packs on this terminal.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sourceRows) { row in
                            Button {
                                fromRowId = row.id
                                if toRowId == row.id { toRowId = nil }
                                localError = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Bin \(row.binNumber) · Game \(row.gameNumber)")
                                            .foregroundColor(.primary)
                                        Text("Pack \(row.packSerial ?? "—") · Begin \(row.beginningNumber.isEmpty ? "—" : row.beginningNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if fromRowId == row.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("To bin (empty)") {
                    if fromRowId == nil {
                        Text("Select a pack first.")
                            .foregroundColor(.secondary)
                    } else if destinationRows.isEmpty {
                        Text("No empty bins. Return or finish a pack first, or add a bin in lottery customization.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(destinationRows) { row in
                            Button {
                                toRowId = row.id
                                localError = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Bin \(row.binNumber)")
                                            .foregroundColor(.primary)
                                        Text(row.gameNumber.isEmpty ? "Empty slot" : "Was game \(row.gameNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if toRowId == row.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                if let source = selectedSource, let toId = toRowId,
                   let dest = destinationRows.first(where: { $0.id == toId }) {
                    Section("Summary") {
                        Text("Move pack \(source.packSerial ?? "") from bin \(source.binNumber) → bin \(dest.binNumber).")
                        Text("Begin # and pack stay the same — no sales change.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .navigationTitle("Move pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        Task { await confirmMove() }
                    }
                    .disabled(!canConfirm)
                }
            }
        }
    }

    private func confirmMove() async {
        guard let fromRowId, let toRowId else { return }
        localError = nil
        do {
            try await viewModel.movePack(fromRowId: fromRowId, toRowId: toRowId)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
