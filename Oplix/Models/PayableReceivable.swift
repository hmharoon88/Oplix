//
//  PayableReceivable.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

enum RecurringFrequency: String, Codable, CaseIterable {
    case none = "none"
    case weekly = "weekly"
    case monthly = "monthly"
    
    var displayName: String {
        switch self {
        case .none: return "One-time"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct Payable: Identifiable, Codable {
    let id: String
    let locationId: String
    let payTo: String // Who to pay
    let amount: Double
    let dueDate: Date? // Optional date for paying
    let createdAt: Date
    let notes: String?
    let frequency: RecurringFrequency // Recurring frequency
    var isPaid: Bool // Whether this payable has been paid
    var paidAt: Date? // Date when it was marked as paid
    var originalPayableId: String? // For recurring items, reference to the original
    
    init(id: String = UUID().uuidString, locationId: String, payTo: String, amount: Double, dueDate: Date? = nil, createdAt: Date = Date(), notes: String? = nil, frequency: RecurringFrequency = .none, isPaid: Bool = false, paidAt: Date? = nil, originalPayableId: String? = nil) {
        self.id = id
        self.locationId = locationId
        self.payTo = payTo
        self.amount = amount
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.notes = notes
        self.frequency = frequency
        self.isPaid = isPaid
        self.paidAt = paidAt
        self.originalPayableId = originalPayableId
    }
    
    enum CodingKeys: String, CodingKey {
        case id, locationId, payTo, amount, dueDate, createdAt, notes, frequency
        case isPaid, paidAt, originalPayableId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        locationId = try container.decode(String.self, forKey: .locationId)
        payTo = try container.decode(String.self, forKey: .payTo)
        amount = try container.decode(Double.self, forKey: .amount)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        frequency = try container.decodeIfPresent(RecurringFrequency.self, forKey: .frequency) ?? .none
        // Handle missing fields with defaults
        isPaid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        originalPayableId = try container.decodeIfPresent(String.self, forKey: .originalPayableId)
    }
}

struct Receivable: Identifiable, Codable {
    let id: String
    let locationId: String
    let receiveFrom: String // Who to receive from
    let amount: Double
    let dueDate: Date? // Optional date for receiving
    let createdAt: Date
    let notes: String?
    let frequency: RecurringFrequency // Recurring frequency
    var isReceived: Bool // Whether this receivable has been received
    var receivedAt: Date? // Date when it was marked as received
    var originalReceivableId: String? // For recurring items, reference to the original
    
    init(id: String = UUID().uuidString, locationId: String, receiveFrom: String, amount: Double, dueDate: Date? = nil, createdAt: Date = Date(), notes: String? = nil, frequency: RecurringFrequency = .none, isReceived: Bool = false, receivedAt: Date? = nil, originalReceivableId: String? = nil) {
        self.id = id
        self.locationId = locationId
        self.receiveFrom = receiveFrom
        self.amount = amount
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.notes = notes
        self.frequency = frequency
        self.isReceived = isReceived
        self.receivedAt = receivedAt
        self.originalReceivableId = originalReceivableId
    }
    
    enum CodingKeys: String, CodingKey {
        case id, locationId, receiveFrom, amount, dueDate, createdAt, notes, frequency
        case isReceived, receivedAt, originalReceivableId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        locationId = try container.decode(String.self, forKey: .locationId)
        receiveFrom = try container.decode(String.self, forKey: .receiveFrom)
        amount = try container.decode(Double.self, forKey: .amount)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        frequency = try container.decodeIfPresent(RecurringFrequency.self, forKey: .frequency) ?? .none
        // Handle missing fields with defaults
        isReceived = try container.decodeIfPresent(Bool.self, forKey: .isReceived) ?? false
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        originalReceivableId = try container.decodeIfPresent(String.self, forKey: .originalReceivableId)
    }
}

