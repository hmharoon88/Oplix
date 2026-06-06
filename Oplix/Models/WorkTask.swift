//
//  Task.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

// How often a task recurs. The reset is implicit: `isCompletedBy(employeeId:)`
// returns false when the stored completion's timestamp is older than the
// current cycle's start, so the row visually "uncompletes" at the cycle
// boundary without needing a scheduled job. Past completion records remain in
// `employeeCompletions` until overwritten by the next cycle's submission.
enum TaskFrequency: String, Codable, CaseIterable {
    case oneTime = "one_time"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var displayName: String {
        switch self {
        case .oneTime: return "One-time"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var shortName: String {
        switch self {
        case .oneTime: return "Once"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var isRecurring: Bool { self != .oneTime }
}

struct WorkTask: Identifiable, Codable {
    let id: String
    let description: String
    var assignedEmployeeIds: [String] // Can be assigned to multiple employees
    var locationId: String? // Optional - nil means manager-level task, not assigned to location yet
    var assignedLocationIds: [String] // Can be assigned to multiple locations
    var employeeCompletions: [String: TaskCompletion] // Track completion per employee (employeeId -> completion info)
    var frequency: TaskFrequency // How often this task recurs (defaults to one-time)
    // Shared across sibling tasks created together via the multi-location
    // corrective flow. Lets the Edit flow propagate description/frequency
    // changes to every location that has the same corrective task. nil for
    // single-location tasks.
    var crossLocationGroupId: String?
    // When the task was first created. Used by the location score helpers to
    // avoid charging a location for daily/weekly cycles that happened
    // *before* the task even existed. Optional so legacy Firestore data
    // (pre-this-field) decodes cleanly — nil falls back to "task has been
    // around forever", same behaviour as before this field shipped.
    var createdAt: Date?

    // Custom decoding to handle missing fields
    enum CodingKeys: String, CodingKey {
        case id
        case description
        case assignedEmployeeIds
        case locationId
        case assignedLocationIds
        case employeeCompletions
        case frequency
        case crossLocationGroupId
        case createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        assignedEmployeeIds = try container.decodeIfPresent([String].self, forKey: .assignedEmployeeIds) ?? []
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        assignedLocationIds = try container.decodeIfPresent([String].self, forKey: .assignedLocationIds) ?? []
        employeeCompletions = try container.decodeIfPresent([String: TaskCompletion].self, forKey: .employeeCompletions) ?? [:]
        // Existing tasks created before this field was added decode as one-time.
        frequency = try container.decodeIfPresent(TaskFrequency.self, forKey: .frequency) ?? .oneTime
        crossLocationGroupId = try container.decodeIfPresent(String.self, forKey: .crossLocationGroupId)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(description, forKey: .description)
        try container.encode(assignedEmployeeIds, forKey: .assignedEmployeeIds)
        try container.encodeIfPresent(locationId, forKey: .locationId)
        try container.encode(assignedLocationIds, forKey: .assignedLocationIds)
        try container.encode(employeeCompletions, forKey: .employeeCompletions)
        try container.encode(frequency, forKey: .frequency)
        try container.encodeIfPresent(crossLocationGroupId, forKey: .crossLocationGroupId)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    init(
        id: String,
        description: String,
        assignedEmployeeIds: [String] = [],
        locationId: String? = nil,
        assignedLocationIds: [String] = [],
        employeeCompletions: [String: TaskCompletion] = [:],
        frequency: TaskFrequency = .oneTime,
        crossLocationGroupId: String? = nil,
        createdAt: Date? = Date()
    ) {
        self.id = id
        self.description = description
        self.assignedEmployeeIds = assignedEmployeeIds
        self.locationId = locationId
        self.assignedLocationIds = assignedLocationIds
        self.employeeCompletions = employeeCompletions
        self.frequency = frequency
        self.crossLocationGroupId = crossLocationGroupId
        self.createdAt = createdAt
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
        // For one-time tasks, "completed" means anyone has ever completed it
        // and that completion hasn't been disapproved by a manager.
        // For recurring tasks, "completed" means anyone has a still-counting
        // completion within the current cycle — disapproved photos and
        // past-cycle completions don't count.
        get {
            if frequency == .oneTime {
                return employeeCompletions.values.contains { $0.countsAsCompleted }
            }
            return currentCycleCompletions.values.contains { $0.countsAsCompleted }
        }
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
    
    // MARK: - Cycle helpers

    /// Start of the current cycle for this task's frequency.
    /// One-time tasks return `.distantPast` so any completion always counts.
    /// Weekly cycles use the user's calendar (locale-aware first weekday); monthly
    /// uses the 1st of the current month.
    func currentCycleStart(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .oneTime:
            return .distantPast
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
        case .monthly:
            return calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
        }
    }

    /// Completions submitted within the current cycle. For one-time tasks this
    /// is just `employeeCompletions`; for recurring it filters out stale entries
    /// from previous cycles so the UI auto-resets at each cycle boundary.
    var currentCycleCompletions: [String: TaskCompletion] {
        if frequency == .oneTime { return employeeCompletions }
        let cycleStart = currentCycleStart()
        return employeeCompletions.filter { _, completion in
            completion.timestamp >= cycleStart
        }
    }

    // MARK: - Helpers
    func isCompletedBy(employeeId: String) -> Bool {
        guard let completion = employeeCompletions[employeeId] else { return false }
        // Disapproved completions don't count — the employee is expected to
        // redo the task, so the row should look "not done" again.
        guard completion.countsAsCompleted else { return false }
        if frequency == .oneTime { return true }
        return completion.timestamp >= currentCycleStart()
    }

    func getCompletion(for employeeId: String) -> TaskCompletion? {
        guard let completion = employeeCompletions[employeeId] else { return nil }
        // For recurring tasks, only return the completion if it's from the current cycle.
        if frequency != .oneTime, completion.timestamp < currentCycleStart() {
            return nil
        }
        return completion
    }
    
    func isAssignedTo(employeeId: String) -> Bool {
        return assignedEmployeeIds.contains(employeeId)
    }
}
