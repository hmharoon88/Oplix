//
//  OhioLotteryBarcodeParser.swift
//  Oplix
//
//  Parses Ohio instant pack/ticket 1D barcodes.
//  Standard: ####-#######-###-#  (e.g. 1091-0017360-000-2)
//  Also:     ###-######-###-#    (e.g. 696-414265-002-8) — common on retail packs.
//  Terminal scanners often return **more digits than the human-readable
//  book number** printed above the barcode (e.g. label `1086-0167066-004-9`
//  but scan `10860167066005108908`). We parse only the leading book-number
//  segment (13, 14, or 15 digits depending on format) and ignore the tail.
//

import Foundation

/// Parsed Ohio instant lottery barcode (pack back or open-book ticket).
struct OhioLotteryBarcode: Equatable {
    let raw: String
    /// Game number (e.g. `1091`, `696`).
    let gameNumber: String
    /// Seven-digit pack / book serial (e.g. `0017360`, `0414265`).
    let packSerial: String
    /// Three-digit ticket position from the barcode (e.g. `000`, `014`).
    let ticketPosition: String
    /// Ticket number for lottery Begin # / End # fields (`000` → `00`, `014` → `14`).
    let ticketNumber: String
    /// Single check digit from the barcode.
    let checkDigit: String
    /// Leading digit run we parsed (matches the printed book number; tail omitted).
    let bookDigits: String

    /// Sealed pack on the rack — ticket position is `000` (first ticket `00`).
    var isSealedPack: Bool { ticketPosition == "000" }

    /// Dashed book number as printed above the barcode (`1086-0167066-004-9`).
    var dashedLabel: String {
        OhioLotteryBarcodeParser.formatDashedLabel(
            gameNumber: gameNumber,
            packSerial: packSerial,
            ticketPosition: ticketPosition,
            checkDigit: checkDigit
        )
    }

    /// How many digits in the raw scan are after the parsed book-number segment.
    var extraScannerDigitCount: Int {
        let scanned = raw.filter(\.isNumber).count
        return max(0, scanned - bookDigits.count)
    }
}

enum OhioLotteryBarcodeParser {

    enum ParseError: Error, Equatable {
        case empty
        case invalidFormat
        case notLotteryBarcode
    }

    /// Normalized game number as stored in the game database (no leading zeros: `696`, `1091`).
    static func canonicalGameNumber(_ game: String) -> String {
        let trimmed = game.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed) { return String(n) }
        return trimmed
    }

    /// Whether a parsed game exists in the global game database.
    static func isKnownGame(_ gameNumber: String, knownGames: Set<String>) -> Bool {
        let canonical = canonicalGameNumber(gameNumber)
        if knownGames.contains(canonical) { return true }
        return knownGames.contains { gameNumbersMatch($0, canonical) }
    }

    /// Game numbers to try when matching legacy DB rows (696 ↔ 0696).
    static func gameLookupCandidates(_ gameNumber: String) -> [String] {
        var candidates: [String] = []
        func add(_ value: String) {
            if !value.isEmpty, !candidates.contains(value) { candidates.append(value) }
        }
        let canonical = canonicalGameNumber(gameNumber)
        add(canonical)
        add(gameNumber)
        if let n = Int(canonical) {
            add(String(format: "%04d", n))
        }
        return candidates
    }

    /// Whether two game numbers refer to the same Ohio game (696 == 0696).
    static func gameNumbersMatch(_ a: String, _ b: String) -> Bool {
        let ta = a.trimmingCharacters(in: .whitespaces)
        let tb = b.trimmingCharacters(in: .whitespaces)
        if let na = Int(ta), let nb = Int(tb) { return na == nb }
        return ta == tb
    }

    /// Whether OCR / printed label text describes the same pack as a barcode scan.
    static func labelsMatch(_ printed: OhioLotteryBarcode, _ scanned: OhioLotteryBarcode) -> Bool {
        printed.gameNumber == scanned.gameNumber
            && printed.packSerial == scanned.packSerial
            && printed.ticketPosition == scanned.ticketPosition
            && printed.checkDigit == scanned.checkDigit
    }

    /// Pull dashed lottery numbers (e.g. `696-414265-002-8`) out of OCR text blobs.
    static func extractPrintedLabelCandidates(from ocrText: String) -> [String] {
        var found: [String] = []
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if parse(trimmed).isSuccess, !found.contains(trimmed) {
            found.append(trimmed)
        }

        // OCR may glue words together — look for embedded ####-######-###-# patterns.
        let pattern = #"\d{3,4}-\d{6,7}-\d{3}-\d"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return found }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        regex.enumerateMatches(in: trimmed, range: range) { match, _, _ in
            guard let match, let swiftRange = Range(match.range, in: trimmed) else { return }
            let candidate = String(trimmed[swiftRange])
            if !found.contains(candidate) { found.append(candidate) }
        }
        return found
    }

    enum PrintedLabelCrossCheck: Equatable {
        case verified
        case noPrintedVisible
        case mismatch(printed: String)
    }

    /// Compare a scanned barcode to printed numbers visible in the camera (OCR).
    static func crossCheckPrintedLabel(barcode: OhioLotteryBarcode, ocrTexts: [String]) -> PrintedLabelCrossCheck {
        let candidates = ocrTexts.flatMap { extractPrintedLabelCandidates(from: $0) }
        guard !candidates.isEmpty else { return .noPrintedVisible }

        for candidate in candidates {
            if case .success(let printed) = parse(candidate), labelsMatch(printed, barcode) {
                return .verified
            }
        }
        return .mismatch(printed: candidates[0])
    }

    /// Quick filter before full parse (scanner debounce / ignore QR URLs).
    static func isLikelyOhioLotteryBarcode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("http") || lower.contains("://") { return false }
        if isRetailProductBarcode(trimmed) { return false }
        return parse(trimmed).isSuccess
    }

    /// UPC / EAN product codes on the ticket face — not Ohio pack barcodes (on the book back).
    static func isRetailProductBarcode(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard !raw.contains("-") else { return false }
        if digits.count == 12 { return true }
        // UPC-A is often scanned as 13-digit EAN with a leading 0.
        if digits.count == 13, digits.first == "0" { return true }
        return false
    }

    static func parse(_ raw: String) -> Result<OhioLotteryBarcode, ParseError> {
        let trimmed = preprocess(raw)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let lower = trimmed.lowercased()
        if lower.contains("http") || lower.contains("://") {
            return .failure(.notLotteryBarcode)
        }

        if isRetailProductBarcode(trimmed) {
            return .failure(.notLotteryBarcode)
        }

        if let parts = matchDashed(trimmed)
            ?? matchCompact(trimmed)
            ?? matchFlexibleDigits(trimmed.filter(\.isNumber)) {
            let bookDigits = bookDigitsForParse(raw: trimmed, parts: parts)
            return .success(makeBarcode(raw: trimmed, parts: parts, bookDigits: bookDigits))
        }

        let digitsOnly = trimmed.filter(\.isNumber)
        if digitsOnly.count == 12 && !trimmed.contains("-") {
            return .failure(.notLotteryBarcode)
        }

        return .failure(.invalidFormat)
    }

    /// Compare pack serials ignoring leading-zero / digit-length differences (`414265` == `0414265`).
    static func packSerialsMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        if let leftInt = Int(left), let rightInt = Int(right) {
            return leftInt == rightInt
        }
        return false
    }

    /// Map Ohio 3-digit ticket position to app ticket number (`000` → `00`).
    static func normalizeTicketPosition(_ ticketPosition: String) -> String {
        guard let value = Int(ticketPosition) else { return "" }
        if value == 0 { return "00" }
        return String(value)
    }

    /// Format parsed fields like the text printed above the barcode.
    static func formatDashedLabel(
        gameNumber: String,
        packSerial: String,
        ticketPosition: String,
        checkDigit: String
    ) -> String {
        let gamePart: String
        if let n = Int(gameNumber), n >= 1000 {
            gamePart = String(format: "%04d", n)
        } else {
            gamePart = gameNumber
        }
        var packPart = packSerial
        if gamePart.count == 3, packSerial.count == 7, packSerial.hasPrefix("0") {
            packPart = String(packSerial.dropFirst())
        }
        return "\(gamePart)-\(packPart)-\(ticketPosition)-\(checkDigit)"
    }

    /// Clean raw scanner text (spaces, control chars, compact digits).
    static func preprocess(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{1d}", with: "")
        s = s.replacingOccurrences(of: "\u{04}", with: "")

        if s.contains(" ") && !s.contains("-") {
            let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
                s = parts.joined(separator: "-")
            } else if parts.count == 1, let only = parts.first {
                s = only
            }
        }

        return s
    }

    // MARK: - Private

    private struct Parts {
        let game: String
        let pack: String
        let ticket: String
        let check: String
        let coreDigitCount: Int
    }

    private static let dashedPattern = #"^(\d{3,4})-(\d{6,7})-(\d{3})-(\d)$"#
    private static let compactPattern = #"^(\d{4})(\d{7})(\d{3})(\d)$"#

    private static func bookDigitsForParse(raw: String, parts: Parts) -> String {
        let digits = raw.filter(\.isNumber)
        return String(digits.prefix(parts.coreDigitCount))
    }

    private static func makeBarcode(raw: String, parts: Parts, bookDigits: String) -> OhioLotteryBarcode {
        let normalized = normalizeParts(parts)
        return OhioLotteryBarcode(
            raw: raw,
            gameNumber: normalized.game,
            packSerial: normalized.pack,
            ticketPosition: normalized.ticket,
            ticketNumber: normalizeTicketPosition(normalized.ticket),
            checkDigit: normalized.check,
            bookDigits: bookDigits
        )
    }

    private static func normalizeParts(_ parts: Parts) -> Parts {
        Parts(
            game: normalizeGameNumber(parts.game),
            pack: normalizePackSerial(parts.pack),
            ticket: parts.ticket,
            check: parts.check,
            coreDigitCount: parts.coreDigitCount
        )
    }

    private static func normalizeGameNumber(_ game: String) -> String {
        canonicalGameNumber(game)
    }

    private static func normalizePackSerial(_ pack: String) -> String {
        if let n = Int(pack) { return String(format: "%07d", n) }
        return pack
    }

    private static func matchDashed(_ value: String) -> Parts? {
        guard let regex = try? NSRegularExpression(pattern: dashedPattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 5,
              let game = capture(value, match: match, index: 1),
              let pack = capture(value, match: match, index: 2),
              let ticket = capture(value, match: match, index: 3),
              let check = capture(value, match: match, index: 4)
        else { return nil }
        return Parts(game: game, pack: pack, ticket: ticket, check: check, coreDigitCount: value.filter(\.isNumber).count)
    }

    private static func matchCompact(_ value: String) -> Parts? {
        let digits = value.filter(\.isNumber)
        guard digits.count == 15 else { return nil }
        guard let regex = try? NSRegularExpression(pattern: compactPattern),
              let match = regex.firstMatch(in: digits, range: NSRange(digits.startIndex..., in: digits)),
              match.numberOfRanges == 5,
              let game = capture(digits, match: match, index: 1),
              let pack = capture(digits, match: match, index: 2),
              let ticket = capture(digits, match: match, index: 3),
              let check = capture(digits, match: match, index: 4)
        else { return nil }
        return Parts(game: game, pack: pack, ticket: ticket, check: check, coreDigitCount: 15)
    }

    /// Ohio retail barcodes: 3-digit game + 6-digit pack + 3-digit ticket + 1 check,
    /// often followed by extra digits in the raw scan (ignore the tail).
    /// Terminal scans may zero-pad the game to 4 digits (0696 + 6-digit pack = 14 core digits).
    private static func matchFlexibleDigits(_ digits: String) -> Parts? {
        let d = String(digits.filter(\.isNumber))
        guard d.count >= 13 else { return nil }

        if d.count == 15 {
            return matchCompact(d)
        }
        if d.count == 14 {
            return matchFourDigitRetail(d)
        }
        if d.count == 13 {
            return matchThreeDigitRetail(d)
        }

        // Long terminal scans: standard 4+7+3+1 (15) vs terminal-padded 0###+6+3+1 (14).
        if d.count >= 19 {
            if d.hasPrefix("0") {
                if let retail = matchFourDigitRetail(String(d.prefix(14))) {
                    return retail
                }
                if let compact = matchCompact(String(d.prefix(15))) {
                    return compact
                }
            } else {
                if let compact = matchCompact(String(d.prefix(15))) {
                    return compact
                }
                if let retail = matchFourDigitRetail(String(d.prefix(14))) {
                    return retail
                }
            }
        }

        // Book label with 3-digit game (696…) and a long tail.
        if d.count >= 18, let retail = matchThreeDigitRetail(String(d.prefix(13))) {
            return retail
        }

        if d.count >= 15, let compact = matchCompact(String(d.prefix(15))) {
            return compact
        }

        if d.count >= 14, let retail = matchFourDigitRetail(String(d.prefix(14))) {
            return retail
        }

        if d.count >= 13 {
            return matchThreeDigitRetail(String(d.prefix(13)))
        }

        return nil
    }

    private static func matchFourDigitRetail(_ digits: String) -> Parts? {
        guard digits.count == 14 else { return nil }
        let game = String(digits.prefix(4))
        var rest = digits.dropFirst(4)
        let pack = String(rest.prefix(6))
        rest = rest.dropFirst(6)
        guard rest.count >= 4 else { return nil }
        let ticket = String(rest.prefix(3))
        let check = String(rest.dropFirst(3).prefix(1))
        return Parts(game: game, pack: pack, ticket: ticket, check: check, coreDigitCount: 14)
    }

    private static func matchThreeDigitRetail(_ digits: String) -> Parts? {
        guard digits.count == 13 else { return nil }
        let game = String(digits.prefix(3))
        var rest = digits.dropFirst(3)
        let pack = String(rest.prefix(6))
        rest = rest.dropFirst(6)
        guard rest.count >= 4 else { return nil }
        let ticket = String(rest.prefix(3))
        let check = String(rest.dropFirst(3).prefix(1))
        return Parts(game: game, pack: pack, ticket: ticket, check: check, coreDigitCount: 13)
    }

    private static func capture(_ value: String, match: NSTextCheckingResult, index: Int) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return nil }
        return String(value[swiftRange])
    }
}

extension Result where Success == OhioLotteryBarcode, Failure == OhioLotteryBarcodeParser.ParseError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
