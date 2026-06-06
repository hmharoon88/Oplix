//
//  User.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let username: String
    let role: UserRole
    var locationId: String? // Can be updated when employee is assigned to locations
    let managerUserId: String? // For employees: the manager who owns their location
    let createdAt: Date
    var organizationName: String? // Organization/company name for managers

    // MARK: - Notification preferences
    //
    // Optional / nil-by-default so existing User docs round-trip with
    // zero new fields written to Firestore. Cloud Functions and the
    // Settings UI both treat `nil` as "all defaults on" — the only way
    // a user opts out is by explicitly toggling something off, which
    // creates the field on demand.
    var notificationPrefs: NotificationPrefs?

    enum UserRole: String, Codable {
        case manager
        case employee
        case supervisor
    }
}

/// Per-user notification preferences. Stored on the User doc as a
/// nested map. Layered as **channels × categories**:
///   - Channel toggles gate transport (push, email).
///   - Category toggles gate event types (tasks, schedule, …).
/// An event is delivered iff the channel is on AND the category is on.
struct NotificationPrefs: Codable, Equatable {
    /// Transport-level master switches.
    var channels: Channels?
    /// Per-event-category opt-outs.
    var categories: Categories?
    /// Quiet hours window for **push only**. Email is always allowed
    /// through (people don't get woken up by an email at 2am).
    var quietHours: QuietHours?

    struct Channels: Codable, Equatable {
        var push: Bool?
        var email: Bool?

        var resolvedPush: Bool { push ?? true }
        var resolvedEmail: Bool { email ?? true }
    }

    struct Categories: Codable, Equatable {
        /// Task assigned / approved / disapproved.
        var tasks: Bool?
        /// Schedule published or changed.
        var schedule: Bool?
        /// Location or role membership changed.
        var assignment: Bool?
        /// Email-only: per-shift summary report.
        var shiftSummary: Bool?
        /// Manager-only: cash variance / over-short alerts.
        var cashAlert: Bool?
        /// Email-only / manager-only: end-of-day digest.
        /// Default-off (opposite of the rest) since digests are opt-in.
        var dailyDigest: Bool?

        var resolvedTasks: Bool { tasks ?? true }
        var resolvedSchedule: Bool { schedule ?? true }
        var resolvedAssignment: Bool { assignment ?? true }
        var resolvedShiftSummary: Bool { shiftSummary ?? true }
        var resolvedCashAlert: Bool { cashAlert ?? true }
        var resolvedDailyDigest: Bool { dailyDigest ?? false }
    }

    struct QuietHours: Codable, Equatable {
        var enabled: Bool?
        /// Start of the quiet window in minutes-from-midnight (0…1440).
        var startMin: Int?
        /// End of the quiet window. Crossing midnight is fine —
        /// e.g. start=1320 (22:00), end=420 (07:00) means 10pm–7am.
        var endMin: Int?

        var resolvedEnabled: Bool { enabled ?? false }
        var resolvedStartMin: Int { startMin ?? (22 * 60) }
        var resolvedEndMin: Int { endMin ?? (7 * 60) }
    }
}

