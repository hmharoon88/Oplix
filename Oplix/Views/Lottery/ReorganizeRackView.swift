//
//  ReorganizeRackView.swift
//  Oplix
//

import SwiftUI

/// Batch rack draft: multiple moves, unassigned holding area, save when clear.
struct ReorganizeRackView: View {
    @ObservedObject var viewModel: LotteryPackInventoryViewModel
    let userId: String
    let userDisplayName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var fromRowId: String?
    @State private var toRowId: String?
    @State private var assignPackId: String?
    @State private var assignToRowId: String?
    @State private var localError: String?
    @State private var showingDiscardAlert = false
    @State private var pendingBackgroundDiscardCheck = false

    private var draftDisplayRows: [LotteryPackRackRow] {
        viewModel.draftRackRows(for: viewModel.selectedTerminal)
    }

    private var movableSourceRows: [LotteryPackRackRow] {
        draftDisplayRows.filter(\.hasActivePack)
    }

    private var canApplyMove: Bool {
        fromRowId != nil && toRowId != nil && fromRowId != toRowId
    }

    private var canApplyAssign: Bool {
        assignPackId != nil && assignToRowId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Draft mode — changes are not live until you save. Lottery close is blocked on this terminal until you save or cancel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Moves keep Begin # and pack serial — no sales change.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.unassignedPacks.isEmpty {
                    Section {
                        Label(
                            "Assign all unassigned packs before saving",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    }
                }

                Section("Move pack (any bin → any bin)") {
                    if movableSourceRows.isEmpty {
                        Text("No active packs on the rack.")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("From bin", selection: $fromRowId) {
                            Text("Select…").tag(String?.none)
                            ForEach(movableSourceRows) { row in
                                Text("Bin \(row.binNumber) · Game \(row.gameNumber)")
                                    .tag(Optional(row.id))
                            }
                        }

                        Picker("To bin", selection: $toRowId) {
                            Text("Select…").tag(String?.none)
                            ForEach(draftDisplayRows) { row in
                                let suffix = row.hasActivePack
                                    ? " · Game \(row.gameNumber)"
                                    : " · empty"
                                Text("Bin \(row.binNumber)\(suffix)")
                                    .tag(Optional(row.id))
                            }
                        }

                        Button("Apply move") {
                            applyMove()
                        }
                        .disabled(!canApplyMove)
                    }
                }

                Section {
                    if viewModel.unassignedPacks.isEmpty {
                        Text("No unassigned packs.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.unassignedPacks) { pack in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Game \(pack.gameNumber) · Pack \(pack.packSerial)")
                                    .font(.subheadline.weight(.semibold))
                                Text("From bin \(pack.fromBinLabel) · Begin \(pack.beginningNumber.isEmpty ? "—" : pack.beginningNumber)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Assign to bin", selection: bindingForAssignDestination(packId: pack.id)) {
                                    Text("Select…").tag(String?.none)
                                    ForEach(draftDisplayRows) { row in
                                        Text("Bin \(row.binNumber)")
                                            .tag(Optional(row.id))
                                    }
                                }
                                .labelsHidden()

                                Button("Assign") {
                                    assignPackId = pack.id
                                    assignToRowId = assignDestination(for: pack.id)
                                    applyAssign()
                                }
                                .disabled(assignDestination(for: pack.id) == nil)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Unassigned (\(viewModel.unassignedPacks.count))")
                } footer: {
                    Text("Packs bumped off a bin during moves land here. Save is disabled until this list is empty.")
                }

                Section("Rack preview") {
                    ForEach(draftDisplayRows) { row in
                        HStack {
                            Text("Bin \(row.binNumber)")
                                .fontWeight(.semibold)
                            Spacer()
                            if row.hasActivePack {
                                Text("Game \(row.gameNumber)")
                                    .font(.caption)
                            } else {
                                Text("Empty")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
            .navigationTitle("Reorganize rack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.hasUnsavedReorganizeChanges || !viewModel.unassignedPacks.isEmpty {
                            showingDiscardAlert = true
                        } else {
                            Task { await cancelAndDismiss() }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveAndDismiss() }
                    }
                    .disabled(!viewModel.canSaveReorganize)
                }
            }
            .alert("Discard rack changes?", isPresented: $showingDiscardAlert) {
                Button("Keep editing", role: .cancel) { }
                Button("Discard", role: .destructive) {
                    Task { await cancelAndDismiss() }
                }
            } message: {
                Text("Unsaved moves and unassigned packs will be lost. The rack stays as it was before reorganize.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, viewModel.hasUnsavedReorganizeChanges || !viewModel.unassignedPacks.isEmpty {
                    pendingBackgroundDiscardCheck = true
                }
                if phase == .active, pendingBackgroundDiscardCheck {
                    pendingBackgroundDiscardCheck = false
                    showingDiscardAlert = true
                }
            }
        }
    }

    private func bindingForAssignDestination(packId: String) -> Binding<String?> {
        Binding(
            get: { assignDestination(for: packId) },
            set: { newValue in
                if assignPackId == packId {
                    assignToRowId = newValue
                } else {
                    assignPackId = packId
                    assignToRowId = newValue
                }
            }
        )
    }

    private func assignDestination(for packId: String) -> String? {
        assignPackId == packId ? assignToRowId : nil
    }

    private func applyMove() {
        guard let from = fromRowId, let to = toRowId else { return }
        localError = nil
        viewModel.draftMovePack(fromRowId: from, toRowId: to)
        fromRowId = nil
        toRowId = nil
    }

    private func applyAssign() {
        guard let packId = assignPackId, let toId = assignToRowId else { return }
        localError = nil
        viewModel.assignUnassignedPack(packId, toRowId: toId)
        assignPackId = nil
        assignToRowId = nil
    }

    private func saveAndDismiss() async {
        localError = nil
        do {
            try await viewModel.saveReorganize(userId: userId)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func cancelAndDismiss() async {
        localError = nil
        do {
            try await viewModel.cancelReorganize(userId: userId)
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}
