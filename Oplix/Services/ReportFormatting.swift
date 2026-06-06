//
//  ReportFormatting.swift
//  Oplix
//

import Foundation

enum ReportFormatting {
    static func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func hours(_ value: Double) -> String {
        String(format: "%.2f hrs", value)
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func overShortLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        let prefix = value >= 0 ? "Over" : "Short"
        return "\(prefix) \(currency(abs(value)))"
    }
}
