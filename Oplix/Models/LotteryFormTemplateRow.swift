//
//  LotteryFormTemplateRow.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

/// Operational state of the physical pack in a bin (optional on legacy rows).
enum LotteryPackStatus: String, Codable, CaseIterable {
    case active
    case returned
    case empty
}

struct LotteryFormTemplateRow: Identifiable, Codable {
    let id: String
    var binNumber: String
    var gameNumber: String
    var value: String
    var tickets: String
    var beginningNumber: String
    var endingNumber: String
    var sold: String
    var dollar: String
    var books: String
    /// Pack serial from barcode (e.g. `0017360` in `1091-0017360-000-2`).
    var packSerial: String?
    var packStatus: LotteryPackStatus?

    init(
        id: String = UUID().uuidString,
        binNumber: String = "",
        gameNumber: String = "",
        value: String = "",
        tickets: String = "",
        beginningNumber: String = "",
        endingNumber: String = "",
        sold: String = "",
        dollar: String = "",
        books: String = "",
        packSerial: String? = nil,
        packStatus: LotteryPackStatus? = nil
    ) {
        self.id = id
        self.binNumber = binNumber
        self.gameNumber = gameNumber
        self.value = value
        self.tickets = tickets
        self.beginningNumber = beginningNumber
        self.endingNumber = endingNumber
        self.sold = sold
        self.dollar = dollar
        self.books = books
        self.packSerial = packSerial
        self.packStatus = packStatus
    }
}
