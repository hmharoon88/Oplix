//
//  LotteryRackReorganizeLock.swift
//  Oplix
//

import Foundation

/// Blocks lottery shift close on this terminal while a rack draft is in progress.
struct LotteryRackReorganizeLock: Codable, Equatable {
    var userId: String
    var userDisplayName: String?
    var startedAt: Date
    var terminalNumber: Int

    /// Locks older than this can be taken over by another manager/supervisor.
    static let staleInterval: TimeInterval = 2 * 60 * 60

    var isStale: Bool {
        Date().timeIntervalSince(startedAt) >= Self.staleInterval
    }
}

/// Pack temporarily off the rack during a reorganize draft session.
struct UnassignedRackPack: Identifiable, Equatable {
    let id: String
    var gameNumber: String
    var value: String
    var tickets: String
    var packSerial: String
    var packStatus: LotteryPackStatus?
    var beginningNumber: String
    var endingNumber: String
    var sold: String
    var dollar: String
    var books: String
    var fromBinLabel: String
}
