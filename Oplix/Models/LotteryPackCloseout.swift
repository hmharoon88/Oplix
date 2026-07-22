//
//  LotteryPackCloseout.swift
//  Oplix
//

import Foundation

enum LotteryPackCloseoutStatus: String, Codable {
    case pending
    case applied
    /// Dropped by correction or rejected as duplicate / sealed-begin ghost credit.
    case voided
}

/// Sold tickets from a finished pack that was replaced mid-shift.
/// Applied (added) to instant sales at the next lottery shift close.
struct LotteryPackCloseout: Identifiable, Codable {
    let id: String
    let locationId: String
    var rowId: String
    var binNumber: String
    var gameNumber: String
    var packSerial: String
    var beginningNumber: String
    var endingNumber: String
    var soldTickets: Int
    var soldDollars: Double
    var books: Int
    var status: LotteryPackCloseoutStatus
    var terminalNumber: Int?
    let createdAt: Date
    var appliedAt: Date?
    var appliedShiftId: String?

    init(
        id: String = UUID().uuidString,
        locationId: String,
        rowId: String,
        binNumber: String,
        gameNumber: String,
        packSerial: String,
        beginningNumber: String,
        endingNumber: String,
        soldTickets: Int,
        soldDollars: Double,
        books: Int,
        status: LotteryPackCloseoutStatus = .pending,
        terminalNumber: Int? = nil,
        createdAt: Date = Date(),
        appliedAt: Date? = nil,
        appliedShiftId: String? = nil
    ) {
        self.id = id
        self.locationId = locationId
        self.rowId = rowId
        self.binNumber = binNumber
        self.gameNumber = gameNumber
        self.packSerial = packSerial
        self.beginningNumber = beginningNumber
        self.endingNumber = endingNumber
        self.soldTickets = soldTickets
        self.soldDollars = soldDollars
        self.books = books
        self.status = status
        self.terminalNumber = terminalNumber
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.appliedShiftId = appliedShiftId
    }
}
