//
//  LotteryForm.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryForm: Identifiable, Codable {
    let id: String
    let locationId: String
    let shiftId: String
    let formData: [String: String]
    let notes: String
    let submittedAt: Date
    var shiftSummary: ShiftSummaryData?

    /// Which terminal this submission was for.
    /// Optional / `nil` means the submission predates multi-terminal
    /// support (legacy single-terminal location). Multi-terminal
    /// locations write one `LotteryForm` per terminal per shift, each
    /// tagged with its `terminalNumber`.
    var terminalNumber: Int?

    init(
        id: String,
        locationId: String,
        shiftId: String,
        formData: [String: String],
        notes: String,
        submittedAt: Date,
        shiftSummary: ShiftSummaryData? = nil,
        terminalNumber: Int? = nil
    ) {
        self.id = id
        self.locationId = locationId
        self.shiftId = shiftId
        self.formData = formData
        self.notes = notes
        self.submittedAt = submittedAt
        self.shiftSummary = shiftSummary
        self.terminalNumber = terminalNumber
    }

    /// Effective terminal number for display / grouping. Treats a
    /// missing value as terminal 1 so legacy submissions render
    /// alongside terminal-1 submissions in the multi-terminal UI.
    var effectiveTerminalNumber: Int { terminalNumber ?? 1 }
}

/// User-facing labels for lottery close-out amounts (`ShiftSummaryData`).
/// Stored field names (`cashInBag`, `cashInBagNet`) stay unchanged in Firestore.
enum LotterySummaryDisplayName {
    static let cashFlowTitle = "Cash in & cash out"

    static let instantSales = "Instant ticket sales"
    static let onlineSales = "Online lottery sales"
    static let registerStartingCash = "Register starting cash"
    static let totalCashIn = "Total cash in"

    static let onlinePayouts = "Online payouts"
    static let instantPayouts = "Instant payouts"
    static let packReturns = "Pack returns"
    static let finishedPackSales = "Finished packs (mid-shift)"
    static let totalCashOut = "Total cash out"

    /// `cashInBag` — sales + register float minus payouts.
    static let balanceAfterCashOut = "Balance after cash out"

    static let lessRegisterFloat = "Less register float"

    /// `cashInBagNet` — lottery-only amount the employee should count.
    static let expectedEnclosedCash = "Expected enclosed cash"

    static let actualEnclosedCash = "Actual enclosed cash"

    static func varianceLabel(for overShort: Double) -> String {
        overShort >= 0 ? "Over" : "Short"
    }
}

extension ShiftSummaryData {
    /// Counted cash enclosed when the shift was closed (`cashInHand`).
    var actualEnclosedCash: Double? {
        guard let overShort else { return nil }
        return cashInBagNet + overShort
    }
}

/// Sanitizes and parses the actual enclosed cash text field (allows negatives).
enum CashEnclosedInput {
    static func sanitize(_ raw: String) -> String {
        var result = ""
        var hasLeadingMinus = false
        var hasDecimal = false
        for (index, character) in raw.enumerated() {
            if character == "-", index == 0, !hasLeadingMinus {
                hasLeadingMinus = true
                result.append(character)
            } else if character == ".", !hasDecimal {
                hasDecimal = true
                result.append(character)
            } else if character.isNumber {
                result.append(character)
            }
        }
        return result
    }

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed != ".", trimmed != "-." else { return nil }
        return Double(trimmed)
    }
}

struct ShiftSummaryData: Codable {
    let totalSold: Int
    let totalDollars: Int
    let totalBooks: Int
    let instantTotal: Double
    let onlineTotal: Double
    let totalSoldAmount: Double
    let registerCash: Double
    let totalCash: Double
    let onlineCashes: Double
    let instantCashes: Double
    let totalCashes: Double
    /// See `LotterySummaryDisplayName.balanceAfterCashOut`.
    let cashInBag: Double
    /// See `LotterySummaryDisplayName.expectedEnclosedCash`.
    let cashInBagNet: Double
    var overShort: Double? // Optional - entered by employee in shift summary
    /// Dollars subtracted at close from pending pack returns.
    var lotteryReturnDeduction: Double?
    /// Dollars added at close from finished packs replaced mid-shift.
    var lotteryPackCloseoutAddition: Double?
    /// Line items for pack returns applied on this close (audit trail).
    var packReturns: [LotteryPackReturnLineItem]?
}

/// One pack return applied (or pending) — shown on shift report and inventory.
struct LotteryPackReturnLineItem: Identifiable, Codable, Equatable {
    var id: String
    var binNumber: String
    var gameNumber: String
    var packSerial: String
    /// Ticket face value as stored on the bin (e.g. "10").
    var ticketValue: String
    var returnedTickets: Int
    var returnedDollars: Double
    var ticketNumber: String

    init(
        id: String = UUID().uuidString,
        binNumber: String,
        gameNumber: String,
        packSerial: String,
        ticketValue: String,
        returnedTickets: Int,
        returnedDollars: Double,
        ticketNumber: String
    ) {
        self.id = id
        self.binNumber = binNumber
        self.gameNumber = gameNumber
        self.packSerial = packSerial
        self.ticketValue = ticketValue
        self.returnedTickets = returnedTickets
        self.returnedDollars = returnedDollars
        self.ticketNumber = ticketNumber
    }

    init(from lotteryReturn: LotteryReturn, ticketValue: String) {
        self.id = lotteryReturn.id
        self.binNumber = lotteryReturn.binNumber
        self.gameNumber = lotteryReturn.gameNumber
        self.packSerial = lotteryReturn.packSerial
        self.ticketValue = ticketValue
        self.returnedTickets = lotteryReturn.returnedTickets
        self.returnedDollars = lotteryReturn.returnedDollars
        self.ticketNumber = lotteryReturn.ticketNumber
    }

    var formattedValue: String {
        let clean = ticketValue.replacingOccurrences(of: "$", with: "")
        return clean.isEmpty ? "—" : "$\(clean)"
    }
}

