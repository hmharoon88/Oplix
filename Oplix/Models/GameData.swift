//
//  GameData.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct GameData: Identifiable, Codable, Equatable {
    let id: String
    var gameNumber: String
    var value: String
    var tickets: String
    let createdAt: Date
    var lastUpdated: Date
    
    init(id: String = UUID().uuidString, gameNumber: String, value: String, tickets: String, createdAt: Date = Date(), lastUpdated: Date = Date()) {
        self.id = id
        self.gameNumber = gameNumber
        self.value = value
        self.tickets = tickets
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
    
    // Equatable conformance - compare by id since that's unique
    static func == (lhs: GameData, rhs: GameData) -> Bool {
        return lhs.id == rhs.id
    }
}

