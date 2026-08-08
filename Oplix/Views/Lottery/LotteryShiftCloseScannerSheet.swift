//
//  LotteryShiftCloseScannerSheet.swift
//  Oplix
//

import SwiftUI
import VisionKit

/// Scan target for a single End # row or continuous rack walk.
struct LotteryShiftCloseScanTarget: Identifiable {
    let id: String
    let binNumber: Int
    let row: LotteryFormTemplateRow

    static func continuous(rows: [LotteryFormTemplateRow]) -> LotteryShiftCloseScanTarget {
        LotteryShiftCloseScanTarget(id: "continuous", binNumber: 0, row: rows.first ?? LotteryFormTemplateRow())
    }

    var isContinuous: Bool { id == "continuous" }
}

struct LotteryShiftCloseScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: LotteryShiftCloseScanTarget
    let rows: [LotteryFormTemplateRow]
    var reverseOrder: Bool = false
    @Binding var rowValues: [String: String]
    /// Persist End # (and optional pack barcode). Returns true if a new pack was added to inventory.
    let onPersistEnding: (String, String, OhioLotteryBarcode?) async throws -> Bool
    /// Returns true if a new pack was added to inventory.
    var onResolveUnrecognizedPack: ((LotteryShiftClosePackReplaceScenario, OhioLotteryBarcode, String, String, String, Bool) async throws -> Bool)? = nil

    @State private var invalidMessage: String?
    @State private var successMessage: String?
    @State private var readyHint: String?
    @State private var lastHandledPayload: String?
    @State private var lastHandledAt = Date.distantPast
    @State private var messageClearTask: Task<Void, Never>?
    @State private var replacePrompt: LotteryShiftClosePackReplacePrompt?
    /// Hard lock so in-flight camera callbacks can't bounce the replace UI.
    @State private var isReplaceFlowLocked = false
    @State private var packsAddedToInventory = 0
    @State private var showingInventorySummary = false

    private let rescanCooldown: TimeInterval = 1.5

    private var scannableRows: [LotteryShiftCloseScanMatcher.RowContext] {
        LotteryShiftCloseScanMatcher.scannableRows(from: rows)
    }

    private var scannedCount: Int {
        scannableRows.filter { !(rowValues[$0.id] ?? "").isEmpty }.count
    }

    private var nextUnscannedBin: Int? {
        scannableRows.first { (rowValues[$0.id] ?? "").isEmpty }?.binNumber
    }

    private var isCameraActive: Bool {
        !isReplaceFlowLocked && replacePrompt == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isCameraActive,
                   DataScannerViewController.isSupported,
                   DataScannerViewController.isAvailable {
                    LotteryBarcodeScannerView(
                        knownGameNumbers: [],
                        continuous: target.isContinuous,
                        playsAcceptFeedback: false,
                        isScanningEnabled: true,
                        onScan: handleScan,
                        onInvalidScan: handleInvalidPayload
                    )
                    // New id each replace cycle so DataScanner is fully torn down.
                    .id("shift-close-scanner-\(isCameraActive)")
                    .ignoresSafeArea()

                    cameraChrome
                } else if replacePrompt == nil {
                    unavailableCamera
                }

                // Full-screen overlay (not .sheet) so continuous camera can't fight presentation.
                if let prompt = replacePrompt {
                    LotteryShiftClosePackReplaceSheet(
                        prompt: prompt,
                        onCancel: {
                            clearReplaceFlow()
                        },
                        onConfirm: { scenario, rowId, returnTicket, ending, creditSealedBeginAsFullBook in
                            guard let onResolveUnrecognizedPack else {
                                throw NSError(
                                    domain: "Oplix",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Pack replace isn’t available here."]
                                )
                            }
                            let added = try await onResolveUnrecognizedPack(scenario, prompt.barcode, rowId, returnTicket, ending, creditSealedBeginAsFullBook)
                            if added { packsAddedToInventory += 1 }
                            rowValues[rowId] = ending
                            let bin = prompt.candidates.first(where: { $0.id == rowId })?.binNumber ?? 0
                            successMessage = "Bin #\(bin) updated → End # \(ending)"
                            LotteryScanFeedback.announceEnding(bin: String(bin), ending: ending)
                            clearReplaceFlow()
                            scheduleMessageClear()
                            if !target.isContinuous {
                                finishScanning()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.secondaryGradient.ignoresSafeArea())
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: replacePrompt?.id)
            .navigationTitle(target.isContinuous ? "Scan bins" : "Scan Bin #\(target.binNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(target.isContinuous ? "Done" : "Cancel") {
                        finishScanning()
                    }
                    .disabled(isReplaceFlowLocked)
                }
            }
            .onAppear {
                if target.isContinuous {
                    readyHint = initialReadyHint
                }
            }
            .alert("Inventory updated", isPresented: $showingInventorySummary) {
                Button("OK") { dismiss() }
            } message: {
                Text(inventorySummaryMessage)
            }
        }
    }

    private var inventorySummaryMessage: String {
        let n = packsAddedToInventory
        if n == 1 {
            return "Added 1 pack to inventory while scanning."
        }
        return "Added \(n) packs to inventory while scanning."
    }

    private func finishScanning() {
        if packsAddedToInventory > 0 {
            showingInventorySummary = true
        } else {
            dismiss()
        }
    }

    private var cameraChrome: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                if let successMessage {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(Color.green.opacity(0.9))
                        .cornerRadius(8)
                }

                if let invalidMessage {
                    Text(invalidMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(8)
                }

                if let readyHint, target.isContinuous {
                    Text(readyHint)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(8)
                }

                if target.isContinuous {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(8)
                } else {
                    Text("Scan the top ticket in Bin #\(target.binNumber).")
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(8)
                }

                Text(target.isContinuous
                     ? "Camera stays open — scan the next bin, rescan to correct, tap Done when finished."
                     : "Point at the barcode on the book — not the UPC on the ticket face.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private var unavailableCamera: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(Theme.cloudBlue)
            Text("Camera scanner isn't available on this device.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var initialReadyHint: String {
        if let next = nextUnscannedBin {
            return "Scan Bin #\(next) — point at the top ticket barcode."
        }
        return "Scan each top ticket — walk the rack in any order."
    }

    private var progressText: String {
        let total = scannableRows.count
        if total == 0 {
            return "No active bins — manager must assign packs first."
        }
        if let next = nextUnscannedBin {
            return "\(scannedCount) of \(total) bins done — next: Bin #\(next)"
        }
        return "All \(total) bins scanned — rescan to correct, or tap Done."
    }

    private func clearReplaceFlow() {
        replacePrompt = nil
        isReplaceFlowLocked = false
    }

    private func scheduleMessageClear() {
        messageClearTask?.cancel()
        messageClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                successMessage = nil
                invalidMessage = nil
                if target.isContinuous {
                    readyHint = nextUnscannedBin.map { "Ready — scan Bin #\($0) next." }
                        ?? "Ready — rescan any bin to correct, or tap Done."
                }
            }
        }
    }

    private func shouldDebouncePayload(_ raw: String) -> Bool {
        guard target.isContinuous else { return false }
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

    private func handleInvalidPayload(_ raw: String) {
        if isReplaceFlowLocked { return }

        if raw.contains("retail UPC")
            || raw.contains("isn't in the database")
            || raw.contains("doesn't match")
            || raw.contains("sealed pack")
            || raw.contains("Bin #")
            || raw.contains("No bin")
            || raw.contains("No active bins")
            || raw.contains("too high")
            || raw.contains("Multiple bins")
            || raw.contains("Couldn't read Ohio") {
            invalidMessage = raw
        } else {
            invalidMessage = "Couldn't read Ohio pack format from: \"\(raw)\". Scan the barcode on the book back or top ticket."
        }
        successMessage = nil
        readyHint = "Wrong barcode — adjust and scan again."
        scheduleMessageClear()
    }

    private func handleScan(_ raw: String) {
        if isReplaceFlowLocked || replacePrompt != nil { return }

        if shouldDebouncePayload(raw) { return }

        guard case .success(let barcode) = OhioLotteryBarcodeParser.parse(raw) else {
            handleInvalidPayload("Couldn't read Ohio pack format. Scan the barcode on the book back or top ticket.")
            LotteryScanFeedback.playError()
            markPayloadHandled(raw)
            return
        }

        let preferredRowId = target.isContinuous ? nil : target.id
        switch LotteryShiftCloseScanMatcher.match(
            barcode: barcode,
            rows: scannableRows,
            preferredRowId: preferredRowId
        ) {
        case .failure(let error):
            handleInvalidPayload(error.localizedDescription)
            LotteryScanFeedback.playError()
            markPayloadHandled(raw)
        case .unrecognizedPack(let barcode, let candidates):
            // Same-game single-bin: seamless Begin→End without the sold-out sheet.
            if let onResolveUnrecognizedPack,
               let seamlessRow = LotteryShiftCloseScanMatcher.autoSeamlessTarget(
                for: barcode,
                among: candidates,
                preferredRowId: preferredRowId
               ) {
                let ending = LotteryShiftCloseScanMatcher.normalizedTicketNumber(barcode.ticketNumber)
                if !ending.isEmpty {
                    isReplaceFlowLocked = true
                    markPayloadHandled(raw)
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
                                clearReplaceFlow()
                            }
                        } catch {
                            await MainActor.run {
                                clearReplaceFlow()
                                handleInvalidPayload(error.localizedDescription)
                                LotteryScanFeedback.playError()
                            }
                        }
                    }
                    return
                }
            }

            // Lock first so queued camera events are ignored before the UI swaps.
            isReplaceFlowLocked = true
            markPayloadHandled(raw)
            invalidMessage = nil
            successMessage = nil
            readyHint = nil
            replacePrompt = LotteryShiftClosePackReplacePrompt(
                barcode: barcode,
                candidates: candidates,
                reverseOrder: reverseOrder
            )
        case .matched(let matched):
            switch LotteryShiftCloseScanMatcher.endingNumber(from: barcode, row: matched) {
            case .failure(let error):
                handleInvalidPayload(error.localizedDescription)
                LotteryScanFeedback.playError()
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

        if target.isContinuous {
            if let next = scannableRows.first(where: { (rowValues[$0.id] ?? "").isEmpty }) {
                readyHint = "Scan Bin #\(next.binNumber) next."
            } else {
                readyHint = "All bins done — scan again to correct, or tap Done."
            }
        }

        scheduleMessageClear()

        if !alreadyPersisted {
            Task {
                do {
                    let added = try await onPersistEnding(matched.id, ending, barcode)
                    await MainActor.run {
                        if added { packsAddedToInventory += 1 }
                    }
                } catch {
                    await MainActor.run {
                        // Don't leave a green "saved" End on screen if Firestore rejected it.
                        rowValues[matched.id] = ""
                        successMessage = nil
                        handleInvalidPayload(error.localizedDescription)
                        LotteryScanFeedback.playError()
                    }
                }
            }
        }

        if !target.isContinuous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                finishScanning()
            }
        }
    }
}
