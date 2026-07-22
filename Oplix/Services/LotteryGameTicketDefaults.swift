//
//  LotteryGameTicketDefaults.swift
//  Oplix
//
//  Infers tickets-per-pack from ticket value using the existing game
//  catalog (most common match), with Ohio lottery fallbacks. $10 packs
//  sometimes differ (50 vs 30), so callers should confirm before saving.
//

import Foundation

enum LotteryGameTicketDefaults {

    /// Standard Ohio book sizes when the catalog has no prior games at that value.
    static let fallbackTicketsByValue: [String: String] = [
        "1": "200",
        "2": "100",
        "5": "50",
        "10": "50",
        "20": "25",
        "30": "25",
        "50": "30"
    ]

    /// Normalize UI / catalog value strings ("$10", "10.0", "10") → "10".
    static func normalizeValue(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("$") {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return "" }
        if let number = Double(s) {
            if number.rounded() == number {
                return String(Int(number))
            }
            // Keep one decimal only when needed (rare for lottery prices).
            return String(number)
        }
        return s
    }

    static func normalizeTickets(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let number = Int(s) {
            return String(number)
        }
        if let number = Double(s), number.rounded() == number, number > 0 {
            return String(Int(number))
        }
        return nil
    }

    /// $10 books are usually 50 tickets but some (e.g. game 1018) are 30.
    static func requiresTicketConfirmation(value: String) -> Bool {
        normalizeValue(value) == "10"
    }

    /// Prefer the most common tickets count among existing games at this value;
    /// otherwise use the Ohio fallback table. Returns nil when unknown.
    static func suggestedTickets(value: String, from games: [GameData]) -> String? {
        let normalized = normalizeValue(value)
        guard !normalized.isEmpty else { return nil }

        let matching = games.compactMap { game -> String? in
            guard normalizeValue(game.value) == normalized else { return nil }
            return normalizeTickets(game.tickets)
        }

        if let mode = mostCommon(matching) {
            return mode
        }
        return fallbackTicketsByValue[normalized]
    }

    /// Human-readable line for the assign sheet.
    static func suggestionCaption(value: String, tickets: String, fromCatalog: Bool) -> String {
        let v = normalizeValue(value)
        if requiresTicketConfirmation(value: v) {
            return fromCatalog
                ? "Most $\(v) games in your database use \(tickets) tickets per pack. Confirm before adding — some $10 games use 30."
                : "$\(v) packs are usually \(tickets) tickets. Confirm before adding — some $10 games use 30."
        }
        return fromCatalog
            ? "Based on your game database, $\(v) games use \(tickets) tickets per pack."
            : "$\(v) packs typically have \(tickets) tickets."
    }

    static func suggestionUsesCatalog(value: String, from games: [GameData]) -> Bool {
        let normalized = normalizeValue(value)
        guard !normalized.isEmpty else { return false }
        return games.contains { normalizeValue($0.value) == normalized && normalizeTickets($0.tickets) != nil }
    }

    private static func mostCommon(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        // Prefer higher count; on ties prefer the larger ticket count (safer book size).
        return counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            let leftTickets = Int(lhs.key) ?? 0
            let rightTickets = Int(rhs.key) ?? 0
            return leftTickets < rightTickets
        })?.key
    }
}
