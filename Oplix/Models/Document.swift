//
//  Document.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Document: Identifiable, Codable {
    let id: String
    let locationId: String
    let name: String
    let fileURL: String // Firebase Storage URL
    let fileType: String // e.g., "pdf", "jpeg", "png", etc.
    let uploadedAt: Date
    var expiryDate: Date? // Optional expiry date
    var dueReminder: DueDateReminder?
    var dueReminderSentOn: String?
    let uploadedBy: String // User ID who uploaded it
    
    enum CodingKeys: String, CodingKey {
        case id
        case locationId
        case name
        case fileURL
        case fileType
        case uploadedAt
        case expiryDate
        case dueReminder
        case dueReminderSentOn
        case uploadedBy
    }
    
    // Regular initializer for creating documents in code
    init(id: String, locationId: String, name: String, fileURL: String, fileType: String, uploadedAt: Date, expiryDate: Date?, uploadedBy: String, dueReminder: DueDateReminder? = nil, dueReminderSentOn: String? = nil) {
        self.id = id
        self.locationId = locationId
        self.name = name
        self.fileURL = fileURL
        self.fileType = fileType
        self.uploadedAt = uploadedAt
        self.expiryDate = expiryDate
        self.dueReminder = dueReminder
        self.dueReminderSentOn = dueReminderSentOn
        self.uploadedBy = uploadedBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        locationId = try container.decode(String.self, forKey: .locationId)
        name = try container.decode(String.self, forKey: .name)
        fileURL = try container.decode(String.self, forKey: .fileURL)
        fileType = try container.decode(String.self, forKey: .fileType)
        uploadedAt = try container.decode(Date.self, forKey: .uploadedAt)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)
        dueReminder = try container.decodeIfPresent(DueDateReminder.self, forKey: .dueReminder)
        dueReminderSentOn = try container.decodeIfPresent(String.self, forKey: .dueReminderSentOn)
        uploadedBy = try container.decode(String.self, forKey: .uploadedBy)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(name, forKey: .name)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(fileType, forKey: .fileType)
        try container.encode(uploadedAt, forKey: .uploadedAt)
        try container.encodeIfPresent(expiryDate, forKey: .expiryDate)
        try container.encodeIfPresent(dueReminder, forKey: .dueReminder)
        try container.encodeIfPresent(dueReminderSentOn, forKey: .dueReminderSentOn)
        try container.encode(uploadedBy, forKey: .uploadedBy)
    }
    
    // Check if document is expiring within a month
    var isExpiringSoon: Bool {
        guard let expiryDate = expiryDate else { return false }
        let calendar = Calendar.current
        let oneMonthFromNow = calendar.date(byAdding: .month, value: 1, to: Date())!
        return expiryDate <= oneMonthFromNow && expiryDate >= Date()
    }
    
    // Check if document has expired
    var isExpired: Bool {
        guard let expiryDate = expiryDate else { return false }
        return expiryDate < Date()
    }
}

