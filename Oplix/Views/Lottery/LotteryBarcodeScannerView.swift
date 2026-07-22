//
//  LotteryBarcodeScannerView.swift
//  Oplix
//

import SwiftUI
import VisionKit
import Vision

/// Set to `true` to cross-check barcode scans against printed numbers above the bars (OCR).
private let enablePrintedLabelOCR = false

/// Symbologies on Ohio instant **pack** labels (book back). Excludes UPC/EAN on ticket face.
private let lotteryScanSymbologies: [VNBarcodeSymbology] = [
    .code128,
    .code39,
    .i2of5,
    .codabar,
]

/// Retail product codes — never Ohio pack barcodes.
private let rejectedRetailSymbologies: Set<VNBarcodeSymbology> = [
    .ean13,
    .ean8,
    .upce,
    .itf14,
]

struct LotteryBarcodeScannerView: UIViewControllerRepresentable {
    let knownGameNumbers: Set<String>
    /// When true, the camera stays open and accepts multiple scans (shift close).
    let continuous: Bool
    /// When false, success sound fires in `onScan` after format parse only — use for shift close where row validation runs in the callback.
    let playsAcceptFeedback: Bool
    /// When false, stop accepting frames (e.g. while a replace sheet is open).
    var isScanningEnabled: Bool = true
    let onScan: (String) -> Void
    let onInvalidScan: ((String) -> Void)?

    init(
        knownGameNumbers: Set<String> = [],
        continuous: Bool = false,
        playsAcceptFeedback: Bool = true,
        isScanningEnabled: Bool = true,
        onScan: @escaping (String) -> Void,
        onInvalidScan: ((String) -> Void)? = nil
    ) {
        self.knownGameNumbers = knownGameNumbers
        self.continuous = continuous
        self.playsAcceptFeedback = playsAcceptFeedback
        self.isScanningEnabled = isScanningEnabled
        self.onScan = onScan
        self.onInvalidScan = onInvalidScan
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        var recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: lotteryScanSymbologies),
        ]
        if enablePrintedLabelOCR {
            recognizedDataTypes.insert(.text(textContentType: nil))
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced,
            recognizesMultipleItems: enablePrintedLabelOCR,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onInvalidScan = onInvalidScan
        context.coordinator.knownGameNumbers = knownGameNumbers
        context.coordinator.continuous = continuous
        context.coordinator.playsAcceptFeedback = playsAcceptFeedback
        context.coordinator.isScanningEnabled = isScanningEnabled
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else { return }
        if isScanningEnabled {
            if !uiViewController.isScanning {
                try? uiViewController.startScanning()
            }
        } else if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            knownGameNumbers: knownGameNumbers,
            continuous: continuous,
            playsAcceptFeedback: playsAcceptFeedback,
            onScan: onScan,
            onInvalidScan: onInvalidScan
        )
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var knownGameNumbers: Set<String>
        var continuous: Bool
        var playsAcceptFeedback: Bool
        var isScanningEnabled: Bool = true
        var onScan: (String) -> Void
        var onInvalidScan: ((String) -> Void)?
        private var didScan = false
        private var lastInvalidPayload: String?
        private var scanCooldownUntil = Date.distantPast
        private var lastHandledPayload: String?
        private var lastHandledAt = Date.distantPast

        private let continuousSuccessCooldown: TimeInterval = 0.9
        private let continuousErrorCooldown: TimeInterval = 0.55

        init(
            knownGameNumbers: Set<String>,
            continuous: Bool,
            playsAcceptFeedback: Bool,
            onScan: @escaping (String) -> Void,
            onInvalidScan: ((String) -> Void)?
        ) {
            self.knownGameNumbers = knownGameNumbers
            self.continuous = continuous
            self.playsAcceptFeedback = playsAcceptFeedback
            self.onScan = onScan
            self.onInvalidScan = onInvalidScan
        }

        private var canAcceptScan: Bool {
            guard isScanningEnabled else { return false }
            if continuous {
                return Date() >= scanCooldownUntil
            }
            return !didScan
        }

        private func shouldHandlePayload(_ payload: String) -> Bool {
            guard canAcceptScan else { return false }
            if continuous,
               payload == lastHandledPayload,
               Date().timeIntervalSince(lastHandledAt) < continuousSuccessCooldown {
                return false
            }
            return true
        }

        private func markHandled(_ payload: String, cooldown: TimeInterval) {
            lastHandledPayload = payload
            lastHandledAt = Date()
            scanCooldownUntil = Date().addingTimeInterval(cooldown)
            if continuous {
                lastInvalidPayload = nil
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            process(item, allItems: [item])
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard canAcceptScan else { return }
            for item in addedItems {
                process(item, allItems: allItems)
                if !continuous, didScan { return }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard canAcceptScan else { return }
            for item in updatedItems {
                process(item, allItems: allItems)
                if !continuous, didScan { return }
            }
        }

        private func process(_ item: RecognizedItem, allItems: [RecognizedItem]) {
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue else { return }

            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard shouldHandlePayload(trimmed) else { return }

            if isRejectedRetailBarcode(barcode) {
                reportInvalid("That's a retail UPC on the ticket face. Scan the pack barcode on the back of the book.")
                return
            }

            guard case .success(let parsedBarcode) = OhioLotteryBarcodeParser.parse(trimmed) else {
                reportInvalid(
                    trimmed,
                    message: "Couldn't read Ohio pack format. Scan the barcode on the book back or top ticket."
                )
                return
            }

            if !knownGameNumbers.isEmpty,
               !OhioLotteryBarcodeParser.isKnownGame(parsedBarcode.gameNumber, knownGames: knownGameNumbers) {
                if !parsedBarcode.isSealedPack {
                    reportInvalid(
                        "Game \(parsedBarcode.gameNumber) isn't in the database. New games must be scanned sealed (ticket 000 / Begin 00 on the book back)."
                    )
                    return
                }
            }

            if enablePrintedLabelOCR {
                let ocrTexts = printedTextsNear(barcodeItem: item, in: allItems)
                switch OhioLotteryBarcodeParser.crossCheckPrintedLabel(barcode: parsedBarcode, ocrTexts: ocrTexts) {
                case .verified, .noPrintedVisible:
                    acceptScan(trimmed)
                case .mismatch(let printed):
                    reportInvalid(
                        "Printed \"\(printed)\" doesn't match barcode \"\(trimmed)\". Center the pack label."
                    )
                }
            } else {
                acceptScan(trimmed)
            }
        }

        private func acceptScan(_ trimmed: String) {
            if continuous {
                // Always record payload so continuous cameras don't flood onScan.
                markHandled(trimmed, cooldown: playsAcceptFeedback ? continuousSuccessCooldown : 1.2)
            } else {
                didScan = true
            }
            deliverOnMain {
                if self.playsAcceptFeedback {
                    LotteryScanFeedback.playSuccess()
                }
                self.onScan(trimmed)
            }
        }

        private func isRejectedRetailBarcode(_ barcode: RecognizedItem.Barcode) -> Bool {
            rejectedRetailSymbologies.contains(barcode.observation.symbology)
        }

        /// OCR lines near the highlighted barcode (prefer text above the bars).
        private func printedTextsNear(barcodeItem: RecognizedItem, in allItems: [RecognizedItem]) -> [String] {
            guard case .barcode(let scannedBarcode) = barcodeItem else {
                return ocrTranscripts(from: allItems)
            }

            let barcodeCenter = center(of: scannedBarcode.bounds)
            let nearText = allItems.compactMap { item -> String? in
                guard case .text(let text) = item else { return nil }
                let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { return nil }

                let textCenter = center(of: text.bounds)
                let horizontalAligned = abs(textCenter.x - barcodeCenter.x) < 0.2
                let verticallyNear = abs(textCenter.y - barcodeCenter.y) < 0.35
                guard horizontalAligned && verticallyNear else { return nil }
                return transcript
            }

            return nearText.isEmpty ? ocrTranscripts(from: allItems) : nearText
        }

        private func center(of bounds: RecognizedItem.Bounds) -> CGPoint {
            let x = (bounds.topLeft.x + bounds.topRight.x + bounds.bottomLeft.x + bounds.bottomRight.x) / 4
            let y = (bounds.topLeft.y + bounds.topRight.y + bounds.bottomLeft.y + bounds.bottomRight.y) / 4
            return CGPoint(x: x, y: y)
        }

        private func ocrTranscripts(from items: [RecognizedItem]) -> [String] {
            items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                return transcript.isEmpty ? nil : transcript
            }
        }

        private func reportInvalid(_ message: String) {
            reportInvalid(nil, message: message)
        }

        private func reportInvalid(_ payload: String?, message: String) {
            if continuous {
                guard canAcceptScan else { return }
                if let payload {
                    markHandled(payload, cooldown: continuousErrorCooldown)
                } else {
                    scanCooldownUntil = Date().addingTimeInterval(continuousErrorCooldown)
                }
                deliverOnMain {
                    LotteryScanFeedback.playError()
                    self.onInvalidScan?(message)
                }
                return
            }

            if lastInvalidPayload != message {
                lastInvalidPayload = message
                deliverOnMain {
                    LotteryScanFeedback.playError()
                    self.onInvalidScan?(message)
                }
            }
        }

        private func deliverOnMain(_ work: @escaping () -> Void) {
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }
    }
}

struct LotteryBarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let knownGameNumbers: Set<String>
    let onScan: (String) -> Void

    @State private var invalidMessage: String?

    init(knownGameNumbers: Set<String> = [], onScan: @escaping (String) -> Void) {
        self.knownGameNumbers = knownGameNumbers
        self.onScan = onScan
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    LotteryBarcodeScannerView(
                        knownGameNumbers: knownGameNumbers,
                        onScan: { value in
                            onScan(value)
                            dismiss()
                        },
                        onInvalidScan: { raw in
                            if raw.contains("game database")
                                || raw.contains("retail UPC")
                                || raw.contains("isn't in the database")
                                || (enablePrintedLabelOCR && raw.contains("doesn't match")) {
                                invalidMessage = raw
                            } else {
                                invalidMessage = "Couldn't read Ohio pack format from: \"\(raw)\". Scan the barcode on the back of the book, not the UPC on the ticket face."
                            }
                        }
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 8) {
                        if let invalidMessage {
                            Text(invalidMessage)
                                .font(.caption)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(10)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(8)
                        }

                        Text("Point at the pack barcode on the back of the book — not the UPC on the ticket face.")
                            .font(.caption)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(8)

                        Text("Tap the highlighted barcode if it doesn't scan automatically.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
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
            }
            .navigationTitle("Scan pack barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
