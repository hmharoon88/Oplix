//
//  LotteryCalculationService.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct LotteryCalculationService {
    
    // MARK: - Sold Tickets Calculation
    
    /// Calculate sold tickets and books based on beginning and ending numbers
    /// - Parameters:
    ///   - beginning: Beginning number (as String, can be "00")
    ///   - ending: Ending number (as String, can be "00")
    ///   - tickets: Total tickets in the book
    ///   - reverseOrder: Whether reverse order is enabled
    /// - Returns: Tuple of (sold: Int, books: Int)
    static func calculateSoldAndBooks(
        beginning: String,
        ending: String,
        tickets: String,
        reverseOrder: Bool
    ) -> (sold: Int, books: Int) {
        let ticketsInt = Int(tickets) ?? 0
        
        // Validate tickets count
        guard ticketsInt > 0 else {
            return (sold: 0, books: 0)
        }
        
        // Maximum valid ticket number is ticketsInt - 1 (e.g., for 25 tickets, max is 24)
        // Valid numbers: 00, 1, 2, 3, ..., maxTicketNumber
        let maxTicketNumber = ticketsInt - 1
        
        // Empty strings are invalid
        guard !beginning.isEmpty, !ending.isEmpty else {
            return (sold: 0, books: 0)
        }
        
        // Normalize "0" to "00" (since "0" represents the first ticket, which is "00")
        // This handles cases where users enter "0" instead of "00"
        // Behavior for different combinations:
        // - "0" + "0" → "00" + "00" → (sold: 0, books: 0) - no tickets sold
        // - "0" + "00" → "00" + "00" → (sold: 0, books: 0) - no tickets sold
        // - "00" + "0" → "00" + "00" → (sold: 0, books: 0) - no tickets sold
        // - "00" + "00" → (sold: 0, books: 0) - no tickets sold
        // - "0" + "5" → "00" + "5" → (sold: 5, books: 0) - normal order: 00 to 5 = 5 tickets
        // - "5" + "0" → "5" + "00" → (sold: depends on order) - wrap case
        let normalizedBeginning = (beginning == "0") ? "00" : beginning
        let normalizedEnding = (ending == "0") ? "00" : ending
        
        // Check if values are "00" or numeric
        let beginningIs00 = normalizedBeginning == "00"
        let endingIs00 = normalizedEnding == "00"
        
        // Convert to integers, validate range
        let beginningNum = beginningIs00 ? nil : (Int(normalizedBeginning) ?? -1)
        let endingNum = endingIs00 ? nil : (Int(normalizedEnding) ?? -1)
        
        // Validate numbers are within range (00 or 1 to maxTicketNumber)
        if let beginNum = beginningNum {
            if beginNum < 1 || beginNum > maxTicketNumber {
                return (sold: 0, books: 0)
            }
        }
        if let endNum = endingNum {
            if endNum < 1 || endNum > maxTicketNumber {
                return (sold: 0, books: 0)
            }
        }
        
        // Special case: both are "00" or same number
        if (beginningIs00 && endingIs00) || 
           (beginningNum != nil && endingNum != nil && beginningNum == endingNum) {
            return (sold: 0, books: 0)
        }
        
        // Helper function to get numeric position for comparison
        // In normal order: 00 < 1 < 2 < ... < 24
        // In reverse order: 24 > 23 > ... > 1 > 00
        func getPosition(is00: Bool, num: Int?, reverse: Bool) -> Int {
            if is00 {
                return reverse ? 0 : -1 // 00 is lowest in normal, highest in reverse
            }
            return num ?? 0
        }
        
        let beginPos = getPosition(is00: beginningIs00, num: beginningNum, reverse: reverseOrder)
        let endPos = getPosition(is00: endingIs00, num: endingNum, reverse: reverseOrder)
        
        if reverseOrder {
            // Reverse order: numbers count down (24, 23, 22, ..., 1, 00, 24, ...)
            // Sequence: 24 > 23 > ... > 1 > 00 > 24 (wrap)
            
            if beginPos > endPos {
                // Normal countdown (no wrap)
                // Example: 24 to 10 = 14 sold, books = 0
                // Example: 10 to 00 = 10 sold, books = 0
                let sold: Int
                if beginningIs00 {
                    // Beginning is 00, ending must be regular number (wrapped case, handled below)
                    return (sold: 0, books: 0) // Shouldn't happen in normal flow
                } else if endingIs00 {
                    // Ending is 00, beginning is regular number
                    sold = beginningNum! // X to 00 = X tickets
                } else {
                    // Both are regular numbers
                    sold = beginningNum! - endingNum!
                }
                return (sold: sold, books: 0)
            } else {
                // Wrap around in reverse order
                // Example: 5 to 20 (reverse wrap) = 5 + (24 - 20) + 1 = 10, books = 1
                let sold: Int
                if beginningIs00 {
                    // 00 to X (reverse wrap) = 1 + (maxTicketNumber - X)
                    sold = 1 + (maxTicketNumber - endingNum!)
                } else if endingIs00 {
                    // X to 00 (reverse wrap) = X + 1
                    sold = beginningNum! + 1
                } else {
                    // Both regular numbers, beginning < ending (wrap)
                    // Example: 5 to 20 with max=24: 5 + (24 - 20) + 1 = 10
                    sold = beginningNum! + (maxTicketNumber - endingNum!) + 1
                }
                return (sold: sold, books: 1)
            }
        } else {
            // Normal order: numbers count up (00, 1, 2, 3, ..., 24, 00, 1, ...)
            // Sequence: 00 < 1 < 2 < ... < 24 < 00 (wrap)
            
            if beginPos < endPos {
                // Normal count up (no wrap)
                // Example: 1 to 10 = 9 sold, books = 0
                // Example: 00 to 5 = 5 sold, books = 0
                let sold: Int
                if beginningIs00 {
                    // Beginning is 00, ending is regular number
                    sold = endingNum! // 00 to X = X tickets
                } else if endingIs00 {
                    // Ending is 00, beginning is regular (wrapped case, handled below)
                    return (sold: 0, books: 0) // Shouldn't happen in normal flow
                } else {
                    // Both are regular numbers
                    sold = endingNum! - beginningNum!
                }
                return (sold: sold, books: 0)
            } else {
                // Wrap around in normal order
                // Example: 20 to 5 (normal wrap) = (24 - 20) + 5 + 1 = 10, books = 1
                let sold: Int
                if beginningIs00 {
                    // 00 to X (normal wrap) shouldn't happen, but handle it
                    sold = endingNum!
                } else if endingIs00 {
                    // X to 00 (normal wrap) = (maxTicketNumber - X) + 1
                    sold = (maxTicketNumber - beginningNum!) + 1
                } else {
                    // Both regular numbers, beginning > ending (wrap)
                    // Example: 20 to 5 with max=24: (24 - 20) + 5 + 1 = 10
                    sold = (maxTicketNumber - beginningNum!) + endingNum! + 1
                }
                return (sold: sold, books: 1)
            }
        }
    }
    
    // MARK: - Dollar Value Calculation
    
    /// Calculate dollar value from sold tickets and game value
    /// - Parameters:
    ///   - sold: Number of tickets sold
    ///   - value: Game value (as String, may include "$")
    /// - Returns: Dollar amount as Int
    static func calculateDollars(sold: Int, value: String) -> Int {
        // Remove "$" and convert to Int
        let cleanValue = value.replacingOccurrences(of: "$", with: "")
        let valueInt = Int(cleanValue) ?? 0
        return sold * valueInt
    }
    
    // MARK: - Template Totals Calculation
    
    /// Calculate totals from lottery form template rows
    /// - Parameters:
    ///   - rows: Array of lottery form template rows
    ///   - reverseOrder: Whether reverse order is enabled
    /// - Returns: Tuple of (totalSold: Int, totalDollars: Int, totalBooks: Int)
    static func calculateTemplateTotals(
        rows: [LotteryFormTemplateRow],
        reverseOrder: Bool
    ) -> (totalSold: Int, totalDollars: Int, totalBooks: Int) {
        var totalSold = 0
        var totalDollars = 0
        var totalBooks = 0
        
        for row in rows {
            // Skip rows that don't have both beginning and ending numbers, or tickets/value
            // We need at least beginning/ending to calculate, or tickets/value for dollar calculation
            let hasBeginningOrEnding = !row.beginningNumber.isEmpty || !row.endingNumber.isEmpty
            let hasTickets = !row.tickets.isEmpty
            let hasValue = !row.value.isEmpty
            
            // Skip if row is completely empty
            guard hasBeginningOrEnding || (hasTickets && hasValue) else { continue }
            
            // Require all fields: beginning, ending, tickets, and value for calculation
            guard !row.beginningNumber.isEmpty && 
                  !row.endingNumber.isEmpty && 
                  !row.tickets.isEmpty &&
                  !row.value.isEmpty else {
                continue // Skip rows missing required fields
            }
            
            // Normalize "0" to "00" for calculation
            let normalizedBeginning = (row.beginningNumber == "0") ? "00" : row.beginningNumber
            let normalizedEnding = (row.endingNumber == "0") ? "00" : row.endingNumber
            
            // Calculate sold and books for this row
            let (sold, books) = calculateSoldAndBooks(
                beginning: normalizedBeginning,
                ending: normalizedEnding,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            
            // Calculate dollars (value is required, so we always calculate)
            let dollars = calculateDollars(sold: sold, value: row.value)
            
            totalSold += sold
            totalDollars += dollars
            totalBooks += books
        }
        
        return (totalSold: totalSold, totalDollars: totalDollars, totalBooks: totalBooks)
    }
    
    // MARK: - Shift Summary Calculation
    
    /// Calculate shift summary from template totals and employee form data
    /// - Parameters:
    ///   - templateTotals: Totals from template (totalSold, totalDollars, totalBooks)
    ///   - onlineTotal: Optional online lottery sales
    ///   - onlineCashes: Optional online winnings paid
    ///   - instantCashes: Optional instant ticket winnings paid
    ///   - registerCash: Optional starting cash in register
    /// - Returns: ShiftSummary with all calculated values
    static func calculateShiftSummary(
        templateTotals: (totalSold: Int, totalDollars: Int, totalBooks: Int),
        onlineTotal: Double?,
        onlineCashes: [String],
        instantCashes: [String],
        registerCash: String?,
        returnDeduction: Double = 0,
        packCloseoutAddition: Double = 0
    ) -> ShiftSummary {
        let instantTotal = max(0, Double(templateTotals.totalDollars) + packCloseoutAddition - returnDeduction)
        let onlineTotalValue = onlineTotal ?? 0.0
        
        // Calculate total sold amount
        let totalSoldAmount = instantTotal + onlineTotalValue
        
        // Parse register cash
        let registerCashValue = parseCashAmount(registerCash) ?? 0.0
        
        // Calculate total cash
        let totalCash = totalSoldAmount + registerCashValue
        
        // Calculate total cashes (payouts)
        let onlineCashesTotal = onlineCashes.compactMap { parseCashAmount($0) }.reduce(0, +)
        let instantCashesTotal = instantCashes.compactMap { parseCashAmount($0) }.reduce(0, +)
        let totalCashes = onlineCashesTotal + instantCashesTotal
        
        // Calculate cash in bag
        let cashInBag = totalCash - totalCashes
        
        // Calculate cash in bag (net)
        let cashInBagNet = cashInBag - registerCashValue
        
        return ShiftSummary(
            totalSold: templateTotals.totalSold,
            totalDollars: templateTotals.totalDollars + Int(packCloseoutAddition.rounded()),
            totalBooks: templateTotals.totalBooks,
            instantTotal: instantTotal,
            onlineTotal: onlineTotalValue,
            totalSoldAmount: totalSoldAmount,
            registerCash: registerCashValue,
            totalCash: totalCash,
            onlineCashes: onlineCashesTotal,
            instantCashes: instantCashesTotal,
            totalCashes: totalCashes,
            cashInBag: cashInBag,
            cashInBagNet: cashInBagNet
        )
    }
    
    // MARK: - Helper Functions
    
    /// Parse cash amount from string (handles "$" and decimals)
    static func parseCashAmount(_ amount: String?) -> Double? {
        guard let amount = amount, !amount.isEmpty else { return nil }
        let cleanAmount = amount.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleanAmount)
    }

    /// Begin # for a brand-new sealed pack on this facility's ticket order.
    static func sealedBeginTicket(ticketsInBook tickets: String, reverseOrder: Bool) -> String {
        if reverseOrder {
            let ticketsInt = Int(tickets) ?? 0
            guard ticketsInt > 0 else { return "00" }
            return String(ticketsInt - 1)
        }
        return "00"
    }

    /// After close, End rolls into next Begin. When End is `00` (book finished),
    /// next Begin is the sealed start for a new pack — `00` forward, top ticket
    /// (e.g. 24) reverse — not a literal finished `00` on reverse racks.
    static func nextBeginAfterClose(
        ending: String,
        ticketsInBook tickets: String,
        reverseOrder: Bool
    ) -> String {
        let normalized = (ending == "0") ? "00" : ending
        if normalized == "00" {
            return sealedBeginTicket(ticketsInBook: tickets, reverseOrder: reverseOrder)
        }
        return ending
    }

    /// Tickets returned on a pack from the scanned ticket position back to `00`.
    static func calculateReturnedTickets(
        fromTicket ticket: String,
        ticketsInBook tickets: String,
        reverseOrder: Bool,
        isSealedPack: Bool
    ) -> Int {
        let ticketsInt = Int(tickets) ?? 0
        guard ticketsInt > 0 else { return 0 }

        if isSealedPack {
            return ticketsInt
        }

        let normalized = (ticket == "0") ? "00" : ticket
        if normalized == "00" {
            return ticketsInt
        }

        let (count, _) = calculateSoldAndBooks(
            beginning: normalized,
            ending: "00",
            tickets: tickets,
            reverseOrder: reverseOrder
        )
        return max(count, 0)
    }

    /// Sold tickets when a pack is finished mid-shift and replaced on the same bin.
    /// Credits Begin → `00`.
    ///
    /// When Begin is already the sealed start (`00` forward / top ticket reverse),
    /// a full-book credit is **not** assumed — that caused West Jeff phantom
    /// thousands when packs were swapped at Begin 00. Pass
    /// `creditFullBookIfSealedBegin: true` only after the employee explicitly
    /// confirms the entire sealed pack sold out.
    static func calculateFinishedPackSold(
        beginning: String,
        ticketsInBook tickets: String,
        reverseOrder: Bool,
        creditFullBookIfSealedBegin: Bool = false
    ) -> (sold: Int, books: Int) {
        let ticketsInt = Int(tickets) ?? 0
        guard ticketsInt > 0 else { return (sold: 0, books: 0) }

        let normalizedBegin = (beginning == "0") ? "00" : beginning
        guard !normalizedBegin.isEmpty else { return (sold: 0, books: 0) }

        let sealedBegin = sealedBeginTicket(ticketsInBook: tickets, reverseOrder: reverseOrder)
        let sealedNorm = (sealedBegin == "0") ? "00" : sealedBegin
        let beginIsSealed = normalizedBegin == sealedNorm

        if beginIsSealed {
            if creditFullBookIfSealedBegin {
                return (sold: ticketsInt, books: 1)
            }
            return (sold: 0, books: 0)
        }

        let (sold, books) = calculateSoldAndBooks(
            beginning: normalizedBegin,
            ending: "00",
            tickets: tickets,
            reverseOrder: reverseOrder
        )
        return (sold: max(sold, 0), books: books)
    }
}

// MARK: - Shift Summary Model

struct ShiftSummary {
    let totalSold: Int
    let totalDollars: Int
    let totalBooks: Int
    let instantTotal: Double
    let onlineTotal: Double
    let totalSoldAmount: Double
    let registerCash: Double
    let totalCash: Double
    let onlineCashes: Double
    let instantCashes: Double
    let totalCashes: Double
    let cashInBag: Double
    let cashInBagNet: Double
}

