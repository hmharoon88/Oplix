//
//  Announcement.swift
//  Oplix
//
//  Broadcast message from a manager (or supervisor) to a cohort of
//  employees. Written by the `sendAnnouncement` Cloud Function and
//  surfaced inside the app via the Announcements inbox.
//
//  Firestore path: users/{managerUserId}/announcements/{announcementId}
//
//  Read state is tracked per-recipient via the `readBy` map, where the
//  key is the recipient's userId and the value is the timestamp they
//  first opened the announcement. The function leaves `readBy` empty;
//  the iOS app fills it lazily as each employee taps in.
//

import Foundation
import FirebaseFirestore

struct Announcement: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var body: String
    /// Optional. `nil` means the announcement was broadcast to all
    /// employees under the owning manager; otherwise it was scoped to
    /// just this location.
    var locationId: String?
    /// User id of whoever composed the announcement (manager or
    /// supervisor). Lets the UI render "from {name}" credit.
    var authorId: String
    /// Server-stamped recipient list at the moment of send. Snapshot,
    /// not a live query — late-joining employees do NOT retroactively
    /// receive past announcements.
    var recipientIds: [String]
    var sentAt: Date
    /// `userId -> firstReadAt`. Drives the unread badge on the
    /// employee/supervisor home and the per-message read count on the
    /// manager history screen.
    var readBy: [String: Date]?

    enum CodingKeys: String, CodingKey {
        case id, title, body, locationId, authorId, recipientIds, sentAt, readBy
    }

    /// True when this specific user hasn't opened the announcement yet.
    func isUnread(for userId: String) -> Bool {
        guard recipientIds.contains(userId) else { return false }
        return (readBy?[userId]) == nil
    }

    /// Convenience: how many of the original recipients have opened the
    /// announcement. Used on the manager history screen.
    var readCount: Int {
        readBy?.count ?? 0
    }
}
