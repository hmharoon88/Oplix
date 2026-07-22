//
//  LotteryShiftCloseScanMatcher.swift
//  Oplix
//

import Foundation

/// Matches Ohio pack/ticket barcodes to lottery template rows at shift close.
enum LotteryShiftCloseScanMatcher {

    enum ScanError: LocalizedError, Equatable {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    struct RowContext: Equatable {
        let id: String
        let binNumber: Int
        let gameNumber: String
        let packSerial: String?
        let beginningNumber: String
        let tickets: String
        let value: String
    }

    enum MatchOutcome: Equatable {
        case matched(RowContext)
        /// Pack serial isn't on the rack, but this game # is — likely swapped mid-shift.
        case unrecognizedPack(barcode: OhioLotteryBarcode, candidates: [RowContext])
        case failure(ScanError)
    }

    /// Rows that should receive an End # scan this shift.
    static func scannableRows(from rows: [LotteryFormTemplateRow]) -> [RowContext] {
        rows.enumerated().compactMap { index, row in
            guard !row.beginningNumber.isEmpty else { return nil }
            guard !row.gameNumber.isEmpty else { return nil }
            if row.packStatus == .returned || row.packStatus == .empty { return nil }
            return RowContext(
                id: row.id,
                binNumber: index + 1,
                gameNumber: row.gameNumber,
                packSerial: row.packSerial,
                beginningNumber: row.beginningNumber,
                tickets: row.tickets,
                value: row.value
            )
        }
    }

    /// Resolve which bin a barcode belongs to, or flag a mid-shift pack swap.
    static func match(
        barcode: OhioLotteryBarcode,
        rows: [RowContext],
        preferredRowId: String? = nil
    ) -> MatchOutcome {
        guard !rows.isEmpty else {
            return .failure(.message("No active bins to scan. Manager must assign packs first."))
        }

        if let preferredRowId,
           let preferred = rows.first(where: { $0.id == preferredRowId }) {
            return validatePreferred(barcode: barcode, for: preferred)
        }

        let serial = barcode.packSerial
        let serialMatches = rows.filter { row in
            OhioLotteryBarcodeParser.packSerialsMatch(row.packSerial, serial)
        }

        if serialMatches.count == 1 {
            return validate(barcode: barcode, for: serialMatches[0])
        }
        if serialMatches.count > 1 {
            return .failure(.message("Multiple bins share pack serial \(serial). Ask a manager to fix pack assignments."))
        }

        let gameMatches = rows.filter {
            OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, barcode.gameNumber)
        }

        let occupiedSameGame = gameMatches.filter { row in
            guard let packSerial = row.packSerial, !packSerial.isEmpty else { return false }
            return !OhioLotteryBarcodeParser.packSerialsMatch(packSerial, serial)
        }

        if !occupiedSameGame.isEmpty {
            return .unrecognizedPack(barcode: barcode, candidates: occupiedBins(from: rows))
        }

        if gameMatches.count == 1 {
            return validate(barcode: barcode, for: gameMatches[0])
        }
        if gameMatches.count > 1 {
            return .failure(.message(
                "Game \(barcode.gameNumber) is in multiple bins. Scan the pack barcode on the book back so we can match the pack serial."
            ))
        }

        // Brand-new game # (or pack not on rack) — let user pick a bin and say returned vs sold.
        let occupied = occupiedBins(from: rows)
        if !occupied.isEmpty {
            return .unrecognizedPack(barcode: barcode, candidates: occupied)
        }

        return .failure(.message(
            "No bin matches pack \(serial) (game \(barcode.gameNumber)), and there are no packs on the rack to replace. Assign this pack in Pack inventory first."
        ))
    }

    /// Bins that currently have a pack (candidates for replace-at-close).
    static func occupiedBins(from rows: [RowContext]) -> [RowContext] {
        rows.filter { row in
            guard let packSerial = row.packSerial, !packSerial.isEmpty else { return false }
            return true
        }
    }

    /// Same-game occupied bins for a scanned pack (seamless Begin→End candidates).
    static func sameGameCandidates(
        for barcode: OhioLotteryBarcode,
        among candidates: [RowContext]
    ) -> [RowContext] {
        candidates.filter {
            OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, barcode.gameNumber)
        }
    }

    /// When exactly one same-game bin is occupied, seamless replace can auto-apply.
    static func autoSeamlessTarget(
        for barcode: OhioLotteryBarcode,
        among candidates: [RowContext],
        preferredRowId: String? = nil
    ) -> RowContext? {
        let sameGame = sameGameCandidates(for: barcode, among: candidates)
        if let preferredRowId,
           let preferred = sameGame.first(where: { $0.id == preferredRowId }) {
            return preferred
        }
        guard sameGame.count == 1 else { return nil }
        return sameGame[0]
    }

    /// Ticket number from barcode, validated against tickets-per-book for the row.
    static func endingNumber(
        from barcode: OhioLotteryBarcode,
        row: RowContext
    ) -> Result<String, ScanError> {
        let ending = normalizedTicketNumber(barcode.ticketNumber)
        guard !ending.isEmpty else {
            return .failure(.message("Couldn't read ticket number from barcode."))
        }

        if barcode.isSealedPack {
            if ticketNumbersEqual(row.beginningNumber, ending) {
                return .success(ending)
            }
            return .failure(.message(
                "Scanned a sealed pack (ticket 00). Scan the top ticket showing the current position in Bin #\(row.binNumber)."
            ))
        }

        if let ticketsInt = Int(row.tickets), ticketsInt > 0, ending != "00" {
            let maxTicket = ticketsInt - 1
            if let entered = Int(ending), entered > maxTicket {
                return .failure(.message(
                    "Ticket \(ending) is too high for this \(row.tickets)-ticket book (max \(maxTicket))."
                ))
            }
        }

        return .success(ending)
    }

    static func normalizedTicketNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return OhioLotteryBarcodeParser.normalizeTicketPosition(trimmed)
    }

    static func ticketNumbersEqual(_ a: String, _ b: String) -> Bool {
        let left = normalizedTicketNumber(a)
        let right = normalizedTicketNumber(b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func validatePreferred(
        barcode: OhioLotteryBarcode,
        for row: RowContext
    ) -> MatchOutcome {
        if let expectedSerial = row.packSerial, !expectedSerial.isEmpty, expectedSerial != barcode.packSerial {
            // Same or different game — offer replace for this targeted bin.
            return .unrecognizedPack(barcode: barcode, candidates: [row])
        }
        if !OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, barcode.gameNumber) {
            if let serial = row.packSerial, !serial.isEmpty {
                return .unrecognizedPack(barcode: barcode, candidates: [row])
            }
            return .failure(.message(
                "Bin #\(row.binNumber) is game \(row.gameNumber), but the scan is game \(barcode.gameNumber)."
            ))
        }
        return validate(barcode: barcode, for: row)
    }

    private static func validate(barcode: OhioLotteryBarcode, for row: RowContext) -> MatchOutcome {
        if let expectedSerial = row.packSerial, !expectedSerial.isEmpty,
           !OhioLotteryBarcodeParser.packSerialsMatch(expectedSerial, barcode.packSerial) {
            return .unrecognizedPack(barcode: barcode, candidates: [row])
        }

        guard OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, barcode.gameNumber) else {
            if let serial = row.packSerial, !serial.isEmpty {
                return .unrecognizedPack(barcode: barcode, candidates: [row])
            }
            return .failure(.message(
                "Bin #\(row.binNumber) is game \(row.gameNumber), but the scan is game \(barcode.gameNumber)."
            ))
        }

        return .matched(row)
    }
}
