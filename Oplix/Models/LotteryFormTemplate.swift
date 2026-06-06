//
//  LotteryFormTemplate.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryFormTemplate: Codable {
    let locationId: String
    var rows: [LotteryFormTemplateRow]
    let lastUpdated: Date
    var lotteryRegisterAmount: String
    var reverseOrder: Bool

    /// Which terminal this template represents at the location.
    /// `nil` (or absent in Firestore) means single-terminal / legacy —
    /// matches every template that existed before multi-terminal support.
    /// Multi-terminal locations store one template per terminal with
    /// `terminalNumber` set to 1, 2, 3, …
    var terminalNumber: Int?

    init(
        locationId: String,
        rows: [LotteryFormTemplateRow] = [],
        lastUpdated: Date = Date(),
        lotteryRegisterAmount: String = "",
        reverseOrder: Bool = false,
        terminalNumber: Int? = nil
    ) {
        self.locationId = locationId
        self.rows = rows
        self.lastUpdated = lastUpdated
        self.lotteryRegisterAmount = lotteryRegisterAmount
        self.reverseOrder = reverseOrder
        self.terminalNumber = terminalNumber
    }

    /// Effective terminal number for storage / display, treating a
    /// missing value as terminal 1 (the legacy single-terminal case).
    var effectiveTerminalNumber: Int { terminalNumber ?? 1 }
}

