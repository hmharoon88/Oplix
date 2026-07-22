//
//  LotteryStockPack.swift
//  Oplix
//
//  Packs received into location stock (not yet on a bin).
//

import Foundation

enum LotteryStockPackStatus: String, Codable {
    case inStock
    case assigned
}

/// A lottery book sitting in inventory before it is placed on a rack bin.
struct LotteryStockPack: Identifiable, Codable, Equatable {
    let id: String
    let locationId: String
    var gameNumber: String
    var packSerial: String
    var value: String
    var tickets: String
    /// Ticket position when received (usually sealed `00`).
    var receivedTicketNumber: String
    var status: LotteryStockPackStatus
    let createdAt: Date
    var assignedAt: Date?
    var assignedRowId: String?
    var assignedBinNumber: String?

    init(
        id: String = UUID().uuidString,
        locationId: String,
        gameNumber: String,
        packSerial: String,
        value: String,
        tickets: String,
        receivedTicketNumber: String = "00",
        status: LotteryStockPackStatus = .inStock,
        createdAt: Date = Date(),
        assignedAt: Date? = nil,
        assignedRowId: String? = nil,
        assignedBinNumber: String? = nil
    ) {
        self.id = id
        self.locationId = locationId
        self.gameNumber = gameNumber
        self.packSerial = packSerial
        self.value = value
        self.tickets = tickets
        self.receivedTicketNumber = receivedTicketNumber
        self.status = status
        self.createdAt = createdAt
        self.assignedAt = assignedAt
        self.assignedRowId = assignedRowId
        self.assignedBinNumber = assignedBinNumber
    }

    var isInStock: Bool { status == .inStock }
}
