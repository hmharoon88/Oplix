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
    let cashInBag: Double
    let cashInBagNet: Double
    var overShort: Double? // Optional - entered by employee in shift summary
}

