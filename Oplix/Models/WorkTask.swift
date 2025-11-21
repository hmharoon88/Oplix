//
//  Task.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct WorkTask: Identifiable, Codable {
    let id: String
    let description: String
    var assignedEmployeeIds: [String] // Can be assigned to multiple employees
    var locationId: String? // Optional - nil means manager-level task, not assigned to location yet
    var assignedLocationIds: [String] // Can be assigned to multiple locations
    var employeeCompletions: [String: TaskCompletion] // Track completion per employee (employeeId -> completion info)
    
    // Custom decoding to handle missing fields
    enum CodingKeys: String, CodingKey {
        case id
        case description
        case assignedEmployeeIds
        case locationId
        case assignedLocationIds
        case employeeCompletions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        assignedEmployeeIds = try container.decodeIfPresent([String].self, forKey: .assignedEmployeeIds) ?? []
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        assignedLocationIds = try container.decodeIfPresent([String].self, forKey: .assignedLocationIds) ?? []
        employeeCompletions = try container.decodeIfPresent([String: TaskCompletion].self, forKey: .employeeCompletions) ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(description, forKey: .description)
        try container.encode(assignedEmployeeIds, forKey: .assignedEmployeeIds)
        try container.encodeIfPresent(locationId, forKey: .locationId)
        try container.encode(assignedLocationIds, forKey: .assignedLocationIds)
        try container.encode(employeeCompletions, forKey: .employeeCompletions)
    }
    
    init(id: String, description: String, assignedEmployeeIds: [String] = [], locationId: String? = nil, assignedLocationIds: [String] = [], employeeCompletions: [String: TaskCompletion] = [:]) {
        self.id = id
        self.description = description
        self.assignedEmployeeIds = assignedEmployeeIds
        self.locationId = locationId
        self.assignedLocationIds = assignedLocationIds
        self.employeeCompletions = employeeCompletions
    }
    
    // Legacy support - for backward compatibility with old Firestore data
    var assignedToEmployeeId: String? {
        get { assignedEmployeeIds.first }
        set {
            if let newValue = newValue {
                if !assignedEmployeeIds.contains(newValue) {
                    assignedEmployeeIds.append(newValue)
                }
            }
        }
    }
    
    var isCompleted: Bool {
        get { !employeeCompletions.isEmpty }
        set { /* Legacy - no longer used */ }
    }
    
    var completionImageURL: String? {
        get { employeeCompletions.values.first?.imageURL }
        set { /* Legacy - no longer used */ }
    }
    
    var completionTimestamp: Date? {
        get { employeeCompletions.values.first?.timestamp }
        set { /* Legacy - no longer used */ }
    }
    
    // Helper methods
    func isCompletedBy(employeeId: String) -> Bool {
        return employeeCompletions[employeeId] != nil
    }
    
    func getCompletion(for employeeId: String) -> TaskCompletion? {
        return employeeCompletions[employeeId]
    }
    
    func isAssignedTo(employeeId: String) -> Bool {
        return assignedEmployeeIds.contains(employeeId)
    }
}
