//
//  LotteryPackCloseoutCalculationTests.swift
//  OplixTests
//

import Testing
@testable import Oplix

struct LotteryPackCloseoutCalculationTests {

    @Test func reverseOrderFinishedFromMidPack() {
        let result = LotteryCalculationService.calculateFinishedPackSold(
            beginning: "10",
            ticketsInBook: "25",
            reverseOrder: true
        )
        #expect(result.sold == 10)
        #expect(result.books == 0)
    }

    @Test func sealedStartDefaultsToNoCredit() {
        let result = LotteryCalculationService.calculateFinishedPackSold(
            beginning: "00",
            ticketsInBook: "30",
            reverseOrder: false
        )
        #expect(result.sold == 0)
        #expect(result.books == 0)
    }

    @Test func sealedStartFinishedCreditsFullBookWhenConfirmed() {
        let result = LotteryCalculationService.calculateFinishedPackSold(
            beginning: "00",
            ticketsInBook: "30",
            reverseOrder: false,
            creditFullBookIfSealedBegin: true
        )
        #expect(result.sold == 30)
        #expect(result.books == 1)
    }

    @Test func reverseSealedStartDefaultsToNoCredit() {
        let result = LotteryCalculationService.calculateFinishedPackSold(
            beginning: "29",
            ticketsInBook: "30",
            reverseOrder: true
        )
        #expect(result.sold == 0)
        #expect(result.books == 0)
    }

    @Test func shiftSummaryAddsCloseoutAndSubtractsReturn() {
        let summary = LotteryCalculationService.calculateShiftSummary(
            templateTotals: (totalSold: 8, totalDollars: 240, totalBooks: 0),
            onlineTotal: 0,
            onlineCashes: [],
            instantCashes: [],
            registerCash: nil,
            returnDeduction: 60,
            packCloseoutAddition: 150
        )
        // 240 + 150 - 60 = 330
        #expect(summary.instantTotal == 330)
        #expect(summary.totalDollars == 390) // 240 + 150
        #expect(summary.totalSoldAmount == 330)
    }
}
