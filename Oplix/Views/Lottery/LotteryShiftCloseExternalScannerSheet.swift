//
//  LotteryShiftCloseExternalScannerSheet.swift
//  Oplix
//

import SwiftUI

/// Bluetooth / USB HID wedge scanner mode for shift close.
/// Keeps a capture field focused, parses Ohio pack barcodes, fills End #,
/// speaks the ending number, and advances to the next unscanned bin.
struct LotteryShiftCloseExternalScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let rows: [LotteryFormTemplateRow]
    var reverseOrder: Bool = false
    @Binding var rowValues: [String: String]
    let onPersistEnding: (String, String, OhioLotteryBarcode?) async throws -> Bool
    var onResolveUnrecognizedPack: ((LotteryShiftClosePackReplaceScenario, OhioLotteryBarcode, String, String, String, Bool) async throws -> Bool)? = nil

    @State private var captureText = ""
    @State private var invalidMessage: String?
    @State private var successMessage: String?
    @State private var readyHint: String?
    @State private var lastHandledPayload: String?
    @State private var lastHandledAt = Date.distantPast
    @State private var messageClearTask: Task<Void, Never>?
    @State private var captureEnabled = true
    @State private var replacePrompt: LotteryShiftClosePackReplacePrompt?
    @State private var packsAddedToInventory = 0
    @State private var showingInventorySummary = false

    private let rescanCooldown: TimeInterval = 0.75

    private var scannableRows: [LotteryShiftCloseScanMatcher.RowContext] {
        LotteryShiftCloseScanMatcher.scannableRows(from: rows)
    }

    private var scannedCount: Int {
        scannableRows.filter { !(rowValues[$0.id] ?? "").isEmpty }.count
    }

    private var nextUnscannedBin: Int? {
        scannableRows.first { (rowValues[$0.id] ?? "").isEmpty }?.binNumber
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    headerCard
                    captureCard
                    statusCard
                    recentBinsCard
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("External scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { finishScanning() }
                }
            }
            .onAppear {
                readyHint = initialReadyHint
            }
            .onDisappear {
                messageClearTask?.cancel()
            }
            .alert("Inventory updated", isPresented: $showingInventorySummary) {
                Button("OK") { dismiss() }
            } message: {
                let n = packsAddedToInventory
                Text(n == 1
                     ? "Added 1 pack to inventory while scanning."
                     : "Added \(n) packs to inventory while scanning.")
            }
            .sheet(item: $replacePrompt) { prompt in
                LotteryShiftClosePackReplaceSheet(
                    prompt: prompt,
                    onCancel: {
                        replacePrompt = nil
                        captureEnabled = true
                    },
                    onConfirm: { scenario, rowId, returnTicket, ending, creditSealedBeginAsFullBook in
                        guard let onResolveUnrecognizedPack else {
                            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pack replace isn’t available here."])
                        }
                        let added = try await onResolveUnrecognizedPack(scenario, prompt.barcode, rowId, returnTicket, ending, creditSealedBeginAsFullBook)
                        if added { packsAddedToInventory += 1 }
                        rowValues[rowId] = ending
                        let bin = prompt.candidates.first(where: { $0.id == rowId })?.binNumber ?? 0
                        successMessage = "Bin #\(bin) updated → End # \(ending)"
                        replacePrompt = nil
                        LotteryScanFeedback.announceEnding(bin: String(bin), ending: ending)
                        scheduleMessageClear()
                        captureEnabled = true
                    }
                )
            }
        }
    }

    private func finishScanning() {
        if packsAddedToInventory > 0 {
            showingInventorySummary = true
        } else {
            dismiss()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bluetooth / plug-in scanner", systemImage: "barcode")
                .font(.headline)
            Text("Pair the scanner as a keyboard, then scan each pack’s top-ticket barcode. The app fills End # and moves to the next empty bin automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(progressText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.cloudBlue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scanner input")
                .font(.subheadline.weight(.semibold))
            LotteryExternalScannerCaptureField(
                text: $captureText,
                isEnabled: captureEnabled,
                onSubmit: handleScan
            )
            .frame(height: 44)

            Text("Keep this screen open. Do not tap into End # fields while scanning.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let successMessage {
                Text(successMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
            }
            if let invalidMessage {
                Text(invalidMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if let readyHint {
                Text(readyHint)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var recentBinsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filled this session")
                .font(.subheadline.weight(.semibold))
            let filled = scannableRows.filter { !(rowValues[$0.id] ?? "").isEmpty }
            if filled.isEmpty {
                Text("No bins scanned yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filled.suffix(8).reversed(), id: \.id) { row in
                    HStack {
                        Text("Bin #\(row.binNumber)")
                        Spacer()
                        Text("End # \(rowValues[row.id] ?? "—")")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }

    private var initialReadyHint: String {
        if let next = nextUnscannedBin {
            return "Ready — scan Bin #\(next) (or any pack; matched by pack serial)."
        }
        return "All bins have End # — rescan to correct, or tap Done."
    }

    private var progressText: String {
        let total = scannableRows.count
        if total == 0 {
            return "No active bins — manager must assign packs first."
        }
        if let next = nextUnscannedBin {
            return "\(scannedCount) of \(total) bins done — next empty: Bin #\(next)"
        }
        return "All \(total) bins scanned — rescan to correct, or tap Done."
    }

    private func scheduleMessageClear() {
        messageClearTask?.cancel()
        messageClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                successMessage = nil
                invalidMessage = nil
                readyHint = nextUnscannedBin.map {
                    "Ready — scan Bin #\($0) next (or any unmatched pack)."
                } ?? "Ready — rescan any bin to correct, or tap Done."
            }
        }
    }

    private func shouldDebouncePayload(_ raw: String) -> Bool {
        if raw == lastHandledPayload,
           Date().timeIntervalSince(lastHandledAt) < rescanCooldown {
            return true
        }
        return false
    }

    private func markPayloadHandled(_ raw: String) {
        lastHandledPayload = raw
        lastHandledAt = Date()
    }

    private func handleInvalidPayload(_ message: String) {
        invalidMessage = message
        successMessage = nil
        readyHint = "Wrong barcode — scan again."
        LotteryScanFeedback.playError()
        scheduleMessageClear()
    }

    private func handleScan(_ raw: String) {
        if shouldDebouncePayload(raw) { return }

        guard case .success(let barcode) = OhioLotteryBarcodeParser.parse(raw) else {
            handleInvalidPayload("Couldn't read Ohio pack format. Scan the barcode on the book back or top ticket.")
            markPayloadHandled(raw)
            return
        }

        switch LotteryShiftCloseScanMatcher.match(
            barcode: barcode,
            rows: scannableRows,
            preferredRowId: nil
        ) {
        case .failure(let error):
            handleInvalidPayload(error.localizedDescription)
            markPayloadHandled(raw)
        case .unrecognizedPack(let barcode, let candidates):
            if let onResolveUnrecognizedPack,
               let seamlessRow = LotteryShiftCloseScanMatcher.autoSeamlessTarget(
                for: barcode,
                among: candidates
               ) {
                let ending = LotteryShiftCloseScanMatcher.normalizedTicketNumber(barcode.ticketNumber)
                if !ending.isEmpty {
                    markPayloadHandled(raw)
                    captureEnabled = false
                    Task {
                        do {
                            let added = try await onResolveUnrecognizedPack(
                                .soldFinished,
                                barcode,
                                seamlessRow.id,
                                "",
                                ending,
                                false
                            )
                            await MainActor.run {
                                if added { packsAddedToInventory += 1 }
                                applyEnding(ending, to: seamlessRow, raw: raw, barcode: nil, alreadyPersisted: true)
                            }
                        } catch {
                            await MainActor.run {
                                captureEnabled = true
                                handleInvalidPayload(error.localizedDescription)
                            }
                        }
                    }
                    return
                }
            }

            markPayloadHandled(raw)
            captureEnabled = false
            replacePrompt = LotteryShiftClosePackReplacePrompt(
                barcode: barcode,
                candidates: candidates,
                reverseOrder: reverseOrder
            )
        case .matched(let matched):
            switch LotteryShiftCloseScanMatcher.endingNumber(from: barcode, row: matched) {
            case .failure(let error):
                handleInvalidPayload(error.localizedDescription)
                markPayloadHandled(raw)
            case .success(let ending):
                applyEnding(ending, to: matched, raw: raw, barcode: barcode, alreadyPersisted: false)
            }
        }
    }

    private func applyEnding(
        _ ending: String,
        to matched: LotteryShiftCloseScanMatcher.RowContext,
        raw: String,
        barcode: OhioLotteryBarcode?,
        alreadyPersisted: Bool
    ) {
        invalidMessage = nil
        rowValues[matched.id] = ending
        successMessage = "Bin #\(matched.binNumber) → End # \(ending)"
        markPayloadHandled(raw)
        LotteryScanFeedback.announceEnding(bin: String(matched.binNumber), ending: ending)

        if let next = scannableRows.first(where: { (rowValues[$0.id] ?? "").isEmpty }) {
            readyHint = "Next empty: Bin #\(next.binNumber)"
        } else {
            readyHint = "All bins done — rescan to correct, or tap Done."
        }

        scheduleMessageClear()

        // Briefly drop focus so speech/UI settle, then reclaim for next wedge scan.
        captureEnabled = false
        Task {
            if !alreadyPersisted {
                do {
                    let added = try await onPersistEnding(matched.id, ending, barcode)
                    await MainActor.run {
                        if added { packsAddedToInventory += 1 }
                    }
                } catch {
                    await MainActor.run {
                        rowValues[matched.id] = ""
                        successMessage = nil
                        handleInvalidPayload(error.localizedDescription)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                captureEnabled = true
            }
        }
    }
}
