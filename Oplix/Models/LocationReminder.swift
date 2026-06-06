//
//  LocationReminder.swift
//  Oplix
//
//  Per-location manager reminders stored under
//  users/{managerId}/locations/{locationId}/reminders/{id}.
//

import Foundation

struct LocationReminder: Identifiable, Codable, Hashable {
    let id: String
    let locationId: String
    var title: String
    var notes: String?
    var dueDate: Date?
    let createdAt: Date
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        locationId: String,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.locationId = locationId
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, locationId, title, notes, dueDate, createdAt, isCompleted, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        locationId = try c.decode(String.self, forKey: .locationId)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
