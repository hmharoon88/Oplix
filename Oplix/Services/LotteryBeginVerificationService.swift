//
//  LotteryBeginVerificationService.swift
//  Oplix
//
//  Detects the "stale Begin numbers" bug at the moment a lottery
//  shift is closed.
//
//  Background: a device whose app sat frozen in the background can
//  hold Begin numbers from an older close. If it closes with them,
//  every ticket the intervening shift sold is counted a second time
//  and the shift shows a false short (Fast Mart 7/16: −$494 that was
//  really $6 over).
//
//  The fingerprint is precise: a stale Begin exactly equals the End
//  from an *older* close while disagreeing with the *latest* close's
//  End. Legitimate Begin changes between closes (pack returned,
//  replaced, or newly assigned) produce sealed/scanned positions that
//  don't match older ends, so they are left alone.
//

import Foundation

struct LotteryBeginCorrection: Equatable {
    let rowId: String
    let binNumber: String
    let gameNumber: String
    let oldBegin: String
    let newBegin: String
}

enum LotteryBeginVerificationService {

    /// "0" and "00" both mean the first ticket; ends/begins are typed
    /// by hand so compare them normalized.
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed == "0" ? "00" : trimmed
    }

    /// Build End-number lookups from recent closes (newest first):
    /// the latest close's ends per row, and the set of ends from the
    /// older closes per row.
    static func endLookups(
        forms: [LotteryForm]
    ) -> (last: [String: String], older: [String: Set<String>]) {
        guard let lastForm = forms.first else { return ([:], [:]) }

        var last: [String: String] = [:]
        for (key, value) in lastForm.formData where key.hasPrefix("row_") {
            last[String(key.dropFirst(4))] = value
        }

        var older: [String: Set<String>] = [:]
        for form in forms.dropFirst() {
            for (key, value) in form.formData where key.hasPrefix("row_") && !value.isEmpty {
                older[String(key.dropFirst(4)), default: []].insert(normalized(value))
            }
        }
        return (last, older)
    }

    /// Rows whose Begin skipped the latest close (stale fingerprint —
    /// see header). Each correction says what the Begin should be:
    /// the latest close's End for that row.
    static func corrections(
        rows: [LotteryFormTemplateRow],
        reverseOrder: Bool,
        lastCloseEnds: [String: String],
        olderEnds: [String: Set<String>]
    ) -> [LotteryBeginCorrection] {
        var result: [LotteryBeginCorrection] = []
        for (index, row) in rows.enumerated() {
            guard !row.beginningNumber.isEmpty else { continue }
            guard let lastEnd = lastCloseEnds[row.id], !lastEnd.isEmpty else { continue }

            let begin = normalized(row.beginningNumber)
            guard begin != normalized(lastEnd) else { continue }

            // A freshly assigned pack legitimately begins at the sealed
            // position, which can coincide with some old close's End on
            // this bin. Never "correct" those — a false positive would
            // overwrite a right number, which is worse than missing a
            // rare stale one.
            let sealedBegin = LotteryCalculationService.sealedBeginTicket(
                ticketsInBook: row.tickets,
                reverseOrder: reverseOrder
            )
            guard begin != normalized(sealedBegin) else { continue }

            guard let older = olderEnds[row.id], older.contains(begin) else { continue }

            result.append(LotteryBeginCorrection(
                rowId: row.id,
                binNumber: row.binNumber.isEmpty ? String(index + 1) : row.binNumber,
                gameNumber: row.gameNumber,
                oldBegin: row.beginningNumber,
                newBegin: lastEnd
            ))
        }
        return result
    }

    /// Employee-facing alert body listing what was refreshed.
    static func alertMessage(for corrections: [LotteryBeginCorrection]) -> String {
        var message = "Your Begin numbers were out of date — another close happened after this screen loaded. They were refreshed to continue from the last close:\n\n"
        for correction in corrections.prefix(8) {
            let game = correction.gameNumber.isEmpty ? "Bin \(correction.binNumber)" : "Game \(correction.gameNumber) (Bin \(correction.binNumber))"
            message += "• \(game): \(correction.oldBegin) → \(correction.newBegin)\n"
        }
        if corrections.count > 8 {
            message += "…and \(corrections.count - 8) more\n"
        }
        message += "\nTotals will be recalculated with the correct numbers. Tap Confirm to close the shift."
        return message
    }
}
