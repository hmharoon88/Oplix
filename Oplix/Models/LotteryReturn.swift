//
//  LotteryReturn.swift
//  Oplix
//

import Foundation

enum LotteryReturnStatus: String, Codable {
    case pending
    case applied
}

/// A pack return waiting to reduce instant sales at the next shift close.
struct LotteryReturn: Identifiable, Codable {
    let id: String
    let locationId: String
    var rowId: String
    var binNumber: String
    var gameNumber: String
    var packSerial: String
    var returnedTickets: Int
    var returnedDollars: Double
    var ticketNumber: String
    /// Face value per ticket at return time (e.g. "10").
    var ticketValue: String?
    /// Begin # on the bin when the return was recorded.
    var beginningNumber: String?
    /// When true, return is rack-only (nothing sold from Begin→return top) — do not subtract at close.
    var skipCloseDeduction: Bool?
    var status: LotteryReturnStatus
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
        returnedTickets: Int,
        returnedDollars: Double,
        ticketNumber: String,
        ticketValue: String? = nil,
        beginningNumber: String? = nil,
        skipCloseDeduction: Bool? = nil,
        status: LotteryReturnStatus = .pending,
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
        self.returnedTickets = returnedTickets
        self.returnedDollars = returnedDollars
        self.ticketNumber = ticketNumber
        self.ticketValue = ticketValue
        self.beginningNumber = beginningNumber
        self.skipCloseDeduction = skipCloseDeduction
        self.status = status
        self.terminalNumber = terminalNumber
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.appliedShiftId = appliedShiftId
    }

    /// Prefer stored value; otherwise derive from dollars ÷ tickets.
    var resolvedTicketValue: String {
        if let ticketValue, !ticketValue.isEmpty { return ticketValue }
        guard returnedTickets > 0 else { return "" }
        let per = returnedDollars / Double(returnedTickets)
        if per == floor(per) { return String(Int(per)) }
        return String(format: "%.2f", per)
    }

    /// Dollars that should hit instant sales at close.
    var closeDeductionDollars: Double {
        if skipCloseDeduction == true { return 0 }
        return returnedDollars
    }
}
