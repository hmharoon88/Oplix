//
//  Expense.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Expense: Identifiable, Codable, Hashable {
    let id: String
    let description: String
    let amount: Double
    let timestamp: Date
    
    init(id: String = UUID().uuidString, description: String, amount: Double, timestamp: Date = Date()) {
        self.id = id
        self.description = description
        self.amount = amount
        self.timestamp = timestamp
    }
}

