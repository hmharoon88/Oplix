//
//  LotteryReturnCalculationTests.swift
//  OplixTests
//

import Testing
@testable import Oplix

struct LotteryReturnCalculationTests {

    @Test func sealedPackReturnsFullBook() {
        let count = LotteryCalculationService.calculateReturnedTickets(
            fromTicket: "00",
            ticketsInBook: "25",
            reverseOrder: false,
            isSealedPack: true
        )
        #expect(count == 25)
    }

    @Test func reverseOrderReturnFromTicketToZero() {
        let count = LotteryCalculationService.calculateReturnedTickets(
            fromTicket: "10",
            ticketsInBook: "25",
            reverseOrder: true,
            isSealedPack: false
        )
        #expect(count == 10)
    }

    @Test func shiftSummarySubtractsReturnDeduction() {
        let summary = LotteryCalculationService.calculateShiftSummary(
            templateTotals: (totalSold: 10, totalDollars: 300, totalBooks: 0),
            onlineTotal: 0,
            onlineCashes: [],
            instantCashes: [],
            registerCash: nil,
            returnDeduction: 60
        )
        #expect(summary.instantTotal == 240)
        #expect(summary.totalSoldAmount == 240)
    }
}
