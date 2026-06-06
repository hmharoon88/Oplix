//
//  Location.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Location: Identifiable, Codable {
    let id: String
    let name: String
    let address: String
    let managerId: String // Manager who owns this location
    var employees: [String] // Employee IDs
    var tasks: [String] // Task IDs
    var lotteryForms: [String] // LotteryForm IDs

    // MARK: - Lottery terminals
    //
    // Most locations have a single lottery terminal — that's the legacy /
    // default behaviour and matches the "one template per location" model
    // the rest of the app was originally built around. Locations that run
    // multiple physical lottery terminals can opt in by raising
    // `lotteryTerminalCount`, at which point the manager edits one
    // template per terminal and employees fill out a per-terminal form
    // at shift close.
    //
    // `lotteryArchivedTerminals` is the set of terminal numbers that
    // were once active but have since been removed (count was reduced).
    // Their templates + history are preserved in Firestore so the
    // manager can re-enable them later by raising the count back up.
    var lotteryTerminalCount: Int? // nil / missing == 1 (single-terminal, legacy behaviour)
    var lotteryArchivedTerminals: [Int]?

    /// Effective terminal count, defaulting to 1 for legacy records
    /// that were stored before multi-terminal support existed.
    var effectiveLotteryTerminalCount: Int {
        max(1, lotteryTerminalCount ?? 1)
    }

    /// Whether this location uses the multi-terminal lottery flow.
    /// The whole UI is gated on this — single-terminal locations see
    /// the original experience byte-for-byte.
    var hasMultipleLotteryTerminals: Bool {
        effectiveLotteryTerminalCount > 1
    }

    /// The terminal numbers an employee can close out today (1...count).
    var activeLotteryTerminalNumbers: [Int] {
        Array(1...effectiveLotteryTerminalCount)
    }
}

