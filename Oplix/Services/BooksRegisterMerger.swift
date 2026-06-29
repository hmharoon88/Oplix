//
//  BooksRegisterMerger.swift
//  Oplix
//
//  Maps shift register closes into web Daily books day documents.
//

import Foundation

struct BooksMergeConflict: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct BooksRegisterSlotUpdate: Equatable {
    let slot: BooksRegisterSlot
    let register: BooksShiftRegister
}

struct BooksMergePlan: Equatable {
    let dayId: String
    let monthId: String
    let slotUpdates: [BooksRegisterSlotUpdate]
    let fuelUpdate: BooksFuelSale?
    let existingDay: BooksDayDoc
    let conflicts: [BooksMergeConflict]

    var hasConflicts: Bool { !conflicts.isEmpty }
}

enum BooksDateIds {
    static func monthId(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    static func dayId(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum BooksRegisterMerger {
    private static let amountTolerance = 0.005

    static func planMerge(
        shift: Shift,
        existingDay: BooksDayDoc?,
        closedAt: Date,
        hasGasStation: Bool,
        calendar: Calendar = .current
    ) -> BooksMergePlan {
        let dayId = BooksDateIds.dayId(from: closedAt, calendar: calendar)
        let monthId = BooksDateIds.monthId(from: closedAt, calendar: calendar)
        let day = existingDay ?? BooksDayDoc.empty(dayId: dayId)

        var slotUpdates: [BooksRegisterSlotUpdate] = []
        var conflicts: [BooksMergeConflict] = []

        let sourceRegisters = registersFromShift(shift)
        for (index, source) in sourceRegisters.enumerated() {
            guard let slot = BooksRegisterSlot.slot(at: index) else {
                conflicts.append(BooksMergeConflict(
                    message: "Register \(index + 1) cannot be mapped — daily books only supports four register shifts per day."
                ))
                continue
            }

            let mapped = booksShiftRegister(from: source)
            guard shiftRegisterHasData(mapped) else { continue }

            let existing = day.shiftRegister(for: slot)
            if shiftRegisterHasData(existing) {
                conflicts.append(BooksMergeConflict(
                    message: conflictMessage(for: slot, existing: existing, dayId: dayId)
                ))
            }

            slotUpdates.append(BooksRegisterSlotUpdate(slot: slot, register: mapped))
        }

        var fuelUpdate: BooksFuelSale?
        if hasGasStation {
            let gallons = sourceRegisters.compactMap(\.fuelSaleGallons).reduce(0, +)
            let dollars = sourceRegisters.compactMap(\.fuelSaleDollars).reduce(0, +)
            if fuelHasData(BooksFuelSale(gallons: gallons, dollars: dollars, regular: 0, midGrade: 0, premium: 0, diesel: 0)) {
                if fuelHasData(day.fuelSale) {
                    conflicts.append(BooksMergeConflict(
                        message: "Fuel totals for \(dayId) already recorded (\(formatGallons(day.fuelSale.gallons)), \(formatCurrency(day.fuelSale.dollars))). Saving will replace them with register fuel (\(formatGallons(gallons)), \(formatCurrency(dollars)))."
                    ))
                }
                fuelUpdate = BooksFuelSale(gallons: gallons, dollars: dollars, regular: 0, midGrade: 0, premium: 0, diesel: 0)
            }
        }

        return BooksMergePlan(
            dayId: dayId,
            monthId: monthId,
            slotUpdates: slotUpdates,
            fuelUpdate: fuelUpdate,
            existingDay: day,
            conflicts: conflicts
        )
    }

    static func apply(plan: BooksMergePlan) -> BooksDayDoc {
        var day = plan.existingDay
        day.dayId = plan.dayId

        for update in plan.slotUpdates {
            day.setShiftRegister(update.register, for: update.slot)
        }

        if let fuel = plan.fuelUpdate {
            day.fuelSale.gallons = fuel.gallons
            day.fuelSale.dollars = fuel.dollars
        }

        return day
    }

    static func overwriteAlertMessage(for plan: BooksMergePlan) -> String {
        let dateLabel = plan.dayId
        let lines = plan.conflicts.map(\.message)
        if lines.isEmpty {
            return "Daily books for \(dateLabel) already has data. Overwrite it with this register close?"
        }
        return "Daily books for \(dateLabel) already has data for the register shift(s) you are saving:\n\n" +
            lines.map { "• \($0)" }.joined(separator: "\n") +
            "\n\nOverwrite existing daily books data?"
    }

    // MARK: - Private

    private static func registersFromShift(_ shift: Shift) -> [Register] {
        if !shift.registers.isEmpty {
            return shift.registers
        }
        if shift.hasRegisterData {
            return [
                Register(
                    cashSale: shift.cashSale,
                    cashInHand: shift.cashInHand,
                    overShort: shift.overShort,
                    creditCard: shift.creditCard
                ),
            ]
        }
        return []
    }

    private static func booksShiftRegister(from register: Register) -> BooksShiftRegister {
        BooksShiftRegister(
            cardSale: register.creditCard ?? 0,
            cashSale: register.cashSale ?? 0,
            overShort: register.overShort ?? 0
        )
    }

    private static func shiftRegisterHasData(_ register: BooksShiftRegister) -> Bool {
        abs(register.cardSale) > amountTolerance ||
            abs(register.cashSale) > amountTolerance ||
            abs(register.overShort) > amountTolerance
    }

    private static func fuelHasData(_ fuel: BooksFuelSale) -> Bool {
        abs(fuel.gallons) > amountTolerance || abs(fuel.dollars) > amountTolerance
    }

    private static func conflictMessage(
        for slot: BooksRegisterSlot,
        existing: BooksShiftRegister,
        dayId: String
    ) -> String {
        var parts: [String] = []
        if abs(existing.cardSale) > amountTolerance {
            parts.append("card \(formatCurrency(existing.cardSale))")
        }
        if abs(existing.cashSale) > amountTolerance {
            parts.append("cash \(formatCurrency(existing.cashSale))")
        }
        if abs(existing.overShort) > amountTolerance {
            parts.append("over/short \(formatCurrency(existing.overShort))")
        }
        let detail = parts.isEmpty ? "existing values" : parts.joined(separator: ", ")
        return "\(slot.displayName) on \(dayId) already has \(detail)."
    }

    private static func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private static func formatGallons(_ gallons: Double) -> String {
        String(format: "%.2f gal", gallons)
    }
}
