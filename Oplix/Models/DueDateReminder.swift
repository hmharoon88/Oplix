//
//  DueDateReminder.swift
//  Oplix
//
//  Per-item due-date reminder settings — synced with `docs/js/due-date-reminder-model.js`.
//

import Foundation

struct DueDateReminder: Codable, Equatable, Hashable {
    var enabled: Bool = false
    /// Days before the due date to fire (0 = on the due date).
    var daysBefore: Int = 0
    var push: Bool = true

    static let daysBeforeOptions: [Int] = [0, 1, 3, 7, 14, 30]

    static func normalized(_ raw: DueDateReminder?) -> DueDateReminder {
        var value = raw ?? DueDateReminder()
        if !daysBeforeOptions.contains(value.daysBefore) {
            value.daysBefore = 0
        }
        return value
    }

    static func label(forDaysBefore days: Int) -> String {
        switch days {
        case 0: return "On due date"
        case 1: return "1 day before"
        default: return "\(days) days before"
        }
    }

    /// Clear the server-side send marker when the user changes reminder timing.
    static func shouldClearSentFlag(
        oldDue: Date?,
        newDue: Date?,
        oldReminder: DueDateReminder?,
        newReminder: DueDateReminder?
    ) -> Bool {
        let oldDay = oldDue.map { Calendar.current.startOfDay(for: $0) }
        let newDay = newDue.map { Calendar.current.startOfDay(for: $0) }
        if oldDay != newDay { return true }
        return normalized(oldReminder) != normalized(newReminder)
    }
}
