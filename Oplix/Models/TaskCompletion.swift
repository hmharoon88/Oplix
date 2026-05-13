//
//  TaskCompletion.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct TaskCompletion: Codable {
    let employeeId: String
    let imageURL: String  // Deprecated: kept for backward compatibility
    let imageURLs: [String]  // New: supports multiple images
    let timestamp: Date

    // MARK: - Manager review

    // Tri-state review state for the photo(s) submitted by the employee:
    //   - nil   → not yet reviewed (default; counts as a completion for the
    //             score, same behaviour as before this field shipped)
    //   - true  → reviewed and approved (counts as a completion)
    //   - false → reviewed and disapproved (does NOT count; the employee has
    //             to redo the task and re-submit a photo)
    //
    // We deliberately keep the disapproved record around (instead of
    // deleting it) so the manager retains the audit trail and can change
    // their mind, and so we can show the employee a "rejected, please redo"
    // banner.
    var isApproved: Bool?
    /// Manager / supervisor user id that reviewed the photo. nil if no
    /// review has happened yet.
    var reviewedBy: String?
    /// When the review action was taken.
    var reviewedAt: Date?
    /// Optional reason a manager left when disapproving. Surfaced to the
    /// employee in the "please redo" banner.
    var disapprovalNote: String?
    /// Optional brief note the employee typed when submitting the
    /// completion photo. Surfaced to the manager during review so the
    /// employee can flag context (e.g. "fridge was already 38°F",
    /// "stockroom was locked, did break room only").
    var note: String?

    init(employeeId: String, imageURL: String, timestamp: Date) {
        self.employeeId = employeeId
        self.imageURL = imageURL
        self.imageURLs = [imageURL]  // Initialize with single image for backward compatibility
        self.timestamp = timestamp
    }

    init(employeeId: String, imageURLs: [String], timestamp: Date, note: String? = nil) {
        self.employeeId = employeeId
        self.imageURL = imageURLs.first ?? ""  // Keep first image for backward compatibility
        self.imageURLs = imageURLs
        self.timestamp = timestamp
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case employeeId
        case imageURL
        case imageURLs
        case timestamp
        case isApproved
        case reviewedBy
        case reviewedAt
        case disapprovalNote
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        employeeId = try container.decode(String.self, forKey: .employeeId)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Try to decode imageURLs first (new format)
        if let urls = try? container.decode([String].self, forKey: .imageURLs) {
            imageURLs = urls
            imageURL = urls.first ?? ""
        } else if let url = try? container.decode(String.self, forKey: .imageURL) {
            // Fallback to single imageURL (old format)
            imageURL = url
            imageURLs = [url]
        } else {
            imageURL = ""
            imageURLs = []
        }

        // Review fields are all optional and missing on legacy data — that's
        // fine, the helpers below treat nil as "not reviewed yet".
        isApproved = try container.decodeIfPresent(Bool.self, forKey: .isApproved)
        reviewedBy = try container.decodeIfPresent(String.self, forKey: .reviewedBy)
        reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        disapprovalNote = try container.decodeIfPresent(String.self, forKey: .disapprovalNote)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(employeeId, forKey: .employeeId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(imageURLs, forKey: .imageURLs)
        try container.encode(imageURL, forKey: .imageURL)  // Keep for backward compatibility
        try container.encodeIfPresent(isApproved, forKey: .isApproved)
        try container.encodeIfPresent(reviewedBy, forKey: .reviewedBy)
        try container.encodeIfPresent(reviewedAt, forKey: .reviewedAt)
        try container.encodeIfPresent(disapprovalNote, forKey: .disapprovalNote)
        try container.encodeIfPresent(note, forKey: .note)
    }

    // MARK: - Convenience

    /// Whether this completion should be counted toward "done" / score
    /// calculations. Disapproved completions don't count; everything else
    /// (approved or not-yet-reviewed) does.
    var countsAsCompleted: Bool {
        isApproved != false
    }

    /// True only when a manager explicitly disapproved the photo. Used by the
    /// employee-side UI to surface a "please redo" banner.
    var isDisapproved: Bool {
        isApproved == false
    }
}

