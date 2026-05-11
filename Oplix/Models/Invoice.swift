//
//  Invoice.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Invoice: Identifiable, Codable {
    let id: String
    let userId: String // Manager user ID
    let locationId: String? // Location ID (optional for backward compatibility)
    let amount: Double
    let description: String
    let fileURL: String? // Firebase Storage URL (for image, PDF, Excel, etc.)
    let fileType: String? // e.g., "jpg", "pdf", "xlsx", etc.
    let fileName: String? // Original file name
    let createdAt: Date
    var paidAt: Date? // Timestamp when paid
    var paidBy: String? // Name of person who paid
    var paymentMethod: PaymentMethod? // Cash or Check
    
    enum PaymentMethod: String, Codable {
        case cash = "Cash"
        case check = "Check"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case locationId
        case amount
        case description
        case fileURL
        case fileType
        case fileName
        case createdAt
        case paidAt
        case paidBy
        case paymentMethod
    }
    
    init(id: String = UUID().uuidString, userId: String, locationId: String? = nil, amount: Double, description: String, fileURL: String?, fileType: String? = nil, fileName: String? = nil, createdAt: Date, paidAt: Date? = nil, paidBy: String? = nil, paymentMethod: PaymentMethod? = nil) {
        self.id = id
        self.userId = userId
        self.locationId = locationId
        self.amount = amount
        self.description = description
        self.fileURL = fileURL
        self.fileType = fileType
        self.fileName = fileName
        self.createdAt = createdAt
        self.paidAt = paidAt
        self.paidBy = paidBy
        self.paymentMethod = paymentMethod
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        amount = try container.decode(Double.self, forKey: .amount)
        description = try container.decode(String.self, forKey: .description)
        fileURL = try container.decodeIfPresent(String.self, forKey: .fileURL)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        paidBy = try container.decodeIfPresent(String.self, forKey: .paidBy)
        paymentMethod = try container.decodeIfPresent(PaymentMethod.self, forKey: .paymentMethod)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(locationId, forKey: .locationId)
        try container.encode(amount, forKey: .amount)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)
        try container.encodeIfPresent(fileType, forKey: .fileType)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(paidAt, forKey: .paidAt)
        try container.encodeIfPresent(paidBy, forKey: .paidBy)
        try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
    }
    
    var isPaid: Bool {
        return paidAt != nil
    }
}

