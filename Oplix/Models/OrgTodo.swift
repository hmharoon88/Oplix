//
//  OrgTodo.swift
//  Oplix
//
//  Organization-level home to-dos — same shape as the manager web app
//  (`docs/js/org-todos-model.js`). Stored at users/{uid}/orgTodos/{id}.
//

import Foundation
import FirebaseFirestore

struct OrgTodo: Identifiable, Equatable {
    let id: String
    var title: String
    var notes: String
    /// `YYYY-MM-DD` string — empty when no due date (matches web).
    var dueDate: String
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        dueDate: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Firestore (web-compatible)

    static func from(document: QueryDocumentSnapshot) -> OrgTodo? {
        let data = document.data()
        let title = (data["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return OrgTodo(
            id: document.documentID,
            title: title,
            notes: (data["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: normalizeDueDate(data["dueDate"]),
            isCompleted: data["isCompleted"] as? Bool ?? false,
            completedAt: parseFlexibleDate(data["completedAt"]),
            createdAt: parseFlexibleDate(data["createdAt"]),
            updatedAt: parseFlexibleDate(data["updatedAt"])
        )
    }

    private static func normalizeDueDate(_ value: Any?) -> String {
        guard let raw = value as? String, !raw.isEmpty else { return "" }
        return String(raw.prefix(10))
    }

    private static func parseFlexibleDate(_ value: Any?) -> Date? {
        if value is NSNull || value == nil { return nil }
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let s = value as? String, !s.isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            return df.date(from: String(s.prefix(10)))
        }
        return nil
    }

    // MARK: - Due-date helpers (mirrors web model)

    private var dueDateValue: Date? {
        guard !dueDate.isEmpty else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        return df.date(from: dueDate)
    }

    private var daysUntilDue: Int? {
        guard let due = dueDateValue else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dueDay = cal.startOfDay(for: due)
        return cal.dateComponents([.day], from: today, to: dueDay).day
    }

    var isOverdue: Bool {
        guard !isCompleted, let days = daysUntilDue else { return false }
        return days < 0
    }

    var isDueToday: Bool {
        guard !isCompleted else { return false }
        return daysUntilDue == 0
    }

    var dueHint: String {
        guard !dueDate.isEmpty, !isCompleted, let days = daysUntilDue else { return "" }
        if days < 0 {
            let n = abs(days)
            return "\(n) day\(n == 1 ? "" : "s") overdue"
        }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        if days <= 7 { return "Due in \(days) days" }
        return ""
    }

    var formattedDueDate: String? {
        guard let due = dueDateValue else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: due)
    }

    static func sorted(_ items: [OrgTodo]) -> [OrgTodo] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted && b.isCompleted }
            let overdueA = a.isOverdue ? 0 : 1
            let overdueB = b.isOverdue ? 0 : 1
            if overdueA != overdueB { return overdueA < overdueB }
            let da = a.daysUntilDue
            let db = b.daysUntilDue
            if let da, let db, da != db { return da < db }
            if da != nil && db == nil { return true }
            if da == nil && db != nil { return false }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    static func openCount(_ items: [OrgTodo]) -> Int {
        items.filter { !$0.isCompleted }.count
    }
}
