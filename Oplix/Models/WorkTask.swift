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
    /// Prior submissions kept when an employee completes again (e.g. a new
    /// daily cycle). Powers the date-grouped History tab on Task Check.
    var completionHistory: [TaskCompletion]

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
        case completionHistory
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
        completionHistory = try container.decodeIfPresent([TaskCompletion].self, forKey: .completionHistory) ?? []
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
        try container.encode(completionHistory, forKey: .completionHistory)
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
        createdAt: Date? = Date(),
        completionHistory: [TaskCompletion] = []
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
        self.completionHistory = completionHistory
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

    // MARK: - Completion history

    /// Stores a new completion and archives the employee's previous
    /// submission (if any) so Task Check History can show past cycles.
    mutating func setEmployeeCompletion(_ completion: TaskCompletion) {
        let employeeId = completion.employeeId
        if let previous = employeeCompletions[employeeId] {
            appendToCompletionHistory(previous)
        }
        employeeCompletions[employeeId] = completion
    }

    private mutating func appendToCompletionHistory(_ completion: TaskCompletion) {
        let alreadyStored = completionHistory.contains { stored in
            stored.employeeId == completion.employeeId
                && abs(stored.timestamp.timeIntervalSince(completion.timestamp)) < 1
        }
        if !alreadyStored {
            completionHistory.append(completion)
        }
    }

    /// Updates approval on the active completion or a matching history row.
    mutating func applyReview(
        employeeId: String,
        completionTimestamp: Date?,
        approved: Bool,
        note: String?,
        reviewerId: String
    ) -> Bool {
        func stamp(_ completion: inout TaskCompletion) {
            completion.isApproved = approved
            completion.reviewedBy = reviewerId
            completion.reviewedAt = Date()
            completion.disapprovalNote = approved ? nil : note
        }

        if let timestamp = completionTimestamp {
            if let current = employeeCompletions[employeeId],
               abs(current.timestamp.timeIntervalSince(timestamp)) < 1 {
                var updated = current
                stamp(&updated)
                employeeCompletions[employeeId] = updated
                return true
            }
            if let index = completionHistory.firstIndex(where: {
                $0.employeeId == employeeId
                    && abs($0.timestamp.timeIntervalSince(timestamp)) < 1
            }) {
                var updated = completionHistory[index]
                stamp(&updated)
                completionHistory[index] = updated
                return true
            }
            return false
        }

        guard var completion = employeeCompletions[employeeId] else { return false }
        stamp(&completion)
        employeeCompletions[employeeId] = completion
        return true
    }

    /// Every stored completion for the History tab (archived cycles plus
    /// current `employeeCompletions`, deduplicated by employee + time).
    func allCompletionsForHistory() -> [TaskCompletion] {
        var entries = completionHistory
        entries.append(contentsOf: employeeCompletions.values)
        return Self.deduplicatedCompletions(entries)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private static func deduplicatedCompletions(_ completions: [TaskCompletion]) -> [TaskCompletion] {
        var seen = Set<String>()
        var result: [TaskCompletion] = []
        for completion in completions {
            let key = "\(completion.employeeId)-\(Int(completion.timestamp.timeIntervalSince1970))"
            if seen.insert(key).inserted {
                result.append(completion)
            }
        }
        return result
    }
}

// MARK: - History list helpers (Task Check)

struct TaskCompletionHistoryEntry: Identifiable {
    let id: String
    let task: WorkTask
    let completion: TaskCompletion

    init(task: WorkTask, completion: TaskCompletion) {
        self.task = task
        self.completion = completion
        id = "\(task.id)-\(completion.employeeId)-\(Int(completion.timestamp.timeIntervalSince1970))"
    }
}

// MARK: - Assignment audit (Task Check History)

/// Per-day assigned / done / missed breakdown for managers and supervisors.
enum TaskAssignmentAudit {
    static let lookbackDays = 30

    struct MissedSlot: Identifiable {
        let id: String
        let task: WorkTask
        let employeeId: String
    }

    struct DaySection: Identifiable {
        let id: Date
        let date: Date
        let assignedCount: Int
        let doneCount: Int
        let missedCount: Int
        let doneEntries: [TaskCompletionHistoryEntry]
        let missedSlots: [MissedSlot]

        var hasContent: Bool {
            assignedCount > 0 || !doneEntries.isEmpty
        }
    }

    static func sections(
        from tasks: [WorkTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DaySection] {
        let assignedTasks = tasks.filter { !$0.assignedEmployeeIds.isEmpty }
        guard !assignedTasks.isEmpty else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: todayStart) else {
            return []
        }

        var dayStarts: [Date] = []
        var cursor = rangeStart
        while cursor <= todayStart {
            dayStarts.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return dayStarts.reversed().compactMap { dayStart in
            buildSection(
                dayStart: dayStart,
                tasks: assignedTasks,
                now: now,
                todayStart: todayStart,
                calendar: calendar
            )
        }
        .filter(\.hasContent)
    }

    private static func buildSection(
        dayStart: Date,
        tasks: [WorkTask],
        now: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> DaySection? {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var assignedCount = 0
        var doneCount = 0
        var missedCount = 0
        var doneEntries: [TaskCompletionHistoryEntry] = []
        var missedSlots: [MissedSlot] = []
        var doneEntryKeys = Set<String>()

        for task in tasks {
            for employeeId in task.assignedEmployeeIds {
                guard isExpected(
                    task: task,
                    employeeId: employeeId,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    todayStart: todayStart,
                    calendar: calendar
                ) else { continue }

                assignedCount += 1

                if let completion = qualifyingCompletion(
                    task: task,
                    employeeId: employeeId,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    todayStart: todayStart,
                    calendar: calendar
                ) {
                    doneCount += 1
                    let entry = TaskCompletionHistoryEntry(task: task, completion: completion)
                    let key = entry.id
                    if doneEntryKeys.insert(key).inserted {
                        doneEntries.append(entry)
                    }
                } else if isMissed(
                    task: task,
                    employeeId: employeeId,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    todayStart: todayStart,
                    calendar: calendar
                ) {
                    missedCount += 1
                    missedSlots.append(
                        MissedSlot(
                            id: "\(task.id)-\(employeeId)-\(Int(dayStart.timeIntervalSince1970))",
                            task: task,
                            employeeId: employeeId
                        )
                    )
                }
            }

            for completion in task.allCompletionsForHistory()
                where task.assignedEmployeeIds.contains(completion.employeeId)
                    && calendar.isDate(completion.timestamp, inSameDayAs: dayStart) {
                let entry = TaskCompletionHistoryEntry(task: task, completion: completion)
                if doneEntryKeys.insert(entry.id).inserted {
                    doneEntries.append(entry)
                    if completion.countsAsCompleted {
                        doneCount += 1
                    }
                }
            }
        }

        doneEntries.sort { $0.completion.timestamp > $1.completion.timestamp }
        missedSlots.sort { $0.task.description.localizedCaseInsensitiveCompare($1.task.description) == .orderedAscending }

        let section = DaySection(
            id: dayStart,
            date: dayStart,
            assignedCount: assignedCount,
            doneCount: doneCount,
            missedCount: missedCount,
            doneEntries: doneEntries,
            missedSlots: missedSlots
        )
        return section.hasContent ? section : nil
    }

    private static func isExpected(
        task: WorkTask,
        employeeId: String,
        dayStart: Date,
        dayEnd: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> Bool {
        guard taskExisted(task: task, onOrBefore: dayEnd, calendar: calendar) else { return false }

        switch task.frequency {
        case .daily:
            return true
        case .weekly:
            return isLastDayOfWeek(dayStart, calendar: calendar)
        case .monthly:
            return isLastDayOfMonth(dayStart, calendar: calendar)
        case .oneTime:
            return !hasQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                before: dayEnd
            )
        }
    }

    private static func isMissed(
        task: WorkTask,
        employeeId: String,
        dayStart: Date,
        dayEnd: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> Bool {
        switch task.frequency {
        case .daily:
            return !hasQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                onSameDayAs: dayStart,
                calendar: calendar
            )
        case .weekly:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: dayStart) else { return false }
            return !hasQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                in: interval.start ..< interval.end
            )
        case .monthly:
            guard let interval = calendar.dateInterval(of: .month, for: dayStart) else { return false }
            return !hasQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                in: interval.start ..< interval.end
            )
        case .oneTime:
            return !hasQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                onSameDayAs: dayStart,
                calendar: calendar
            )
        }
    }

    private static func qualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        dayStart: Date,
        dayEnd: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> TaskCompletion? {
        switch task.frequency {
        case .daily:
            return firstQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                onSameDayAs: dayStart,
                calendar: calendar
            )
        case .weekly:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: dayStart) else { return nil }
            return firstQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                in: interval.start ..< interval.end
            )
        case .monthly:
            guard let interval = calendar.dateInterval(of: .month, for: dayStart) else { return nil }
            return firstQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                in: interval.start ..< interval.end
            )
        case .oneTime:
            return firstQualifyingCompletion(
                task: task,
                employeeId: employeeId,
                onSameDayAs: dayStart,
                calendar: calendar
            )
        }
    }

    private static func taskExisted(task: WorkTask, onOrBefore dayEnd: Date, calendar: Calendar) -> Bool {
        guard let created = task.createdAt else { return true }
        return calendar.startOfDay(for: created) < dayEnd
    }

    private static func isLastDayOfWeek(_ day: Date, calendar: Calendar) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return !calendar.isDate(day, equalTo: next, toGranularity: .weekOfYear)
    }

    private static func isLastDayOfMonth(_ day: Date, calendar: Calendar) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return !calendar.isDate(day, equalTo: next, toGranularity: .month)
    }

    private static func hasQualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        before dayEnd: Date
    ) -> Bool {
        task.allCompletionsForHistory().contains {
            $0.employeeId == employeeId
                && $0.countsAsCompleted
                && $0.timestamp < dayEnd
        }
    }

    private static func hasQualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        onSameDayAs dayStart: Date,
        calendar: Calendar
    ) -> Bool {
        firstQualifyingCompletion(
            task: task,
            employeeId: employeeId,
            onSameDayAs: dayStart,
            calendar: calendar
        ) != nil
    }

    private static func hasQualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        in range: Range<Date>
    ) -> Bool {
        firstQualifyingCompletion(task: task, employeeId: employeeId, in: range) != nil
    }

    private static func firstQualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        onSameDayAs dayStart: Date,
        calendar: Calendar
    ) -> TaskCompletion? {
        task.allCompletionsForHistory()
            .filter {
                $0.employeeId == employeeId
                    && $0.countsAsCompleted
                    && calendar.isDate($0.timestamp, inSameDayAs: dayStart)
            }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    private static func firstQualifyingCompletion(
        task: WorkTask,
        employeeId: String,
        in range: Range<Date>
    ) -> TaskCompletion? {
        task.allCompletionsForHistory()
            .filter {
                $0.employeeId == employeeId
                    && $0.countsAsCompleted
                    && $0.timestamp >= range.lowerBound
                    && $0.timestamp < range.upperBound
            }
            .max(by: { $0.timestamp < $1.timestamp })
    }
}
