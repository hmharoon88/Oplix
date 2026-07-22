//
//  LotteryGameTicketDefaultsTests.swift
//  OplixTests
//

import Testing
@testable import Oplix

struct LotteryGameTicketDefaultsTests {

    @Test func normalizesDollarAndDecimalValues() {
        #expect(LotteryGameTicketDefaults.normalizeValue("$10") == "10")
        #expect(LotteryGameTicketDefaults.normalizeValue("10.0") == "10")
        #expect(LotteryGameTicketDefaults.normalizeValue(" 5 ") == "5")
    }

    @Test func usesFallbackWhenCatalogEmpty() {
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "1", from: []) == "200")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "2", from: []) == "100")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "5", from: []) == "50")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "10", from: []) == "50")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "20", from: []) == "25")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "30", from: []) == "25")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "50", from: []) == "30")
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "3", from: []) == nil)
    }

    @Test func prefersMostCommonTicketsFromCatalog() {
        let games = [
            GameData(gameNumber: "1", value: "10", tickets: "50"),
            GameData(gameNumber: "2", value: "10", tickets: "50"),
            GameData(gameNumber: "1018", value: "10", tickets: "30")
        ]
        #expect(LotteryGameTicketDefaults.suggestedTickets(value: "10", from: games) == "50")
    }

    @Test func tenDollarRequiresConfirmation() {
        #expect(LotteryGameTicketDefaults.requiresTicketConfirmation(value: "10"))
        #expect(LotteryGameTicketDefaults.requiresTicketConfirmation(value: "$10.00"))
        #expect(!LotteryGameTicketDefaults.requiresTicketConfirmation(value: "5"))
    }
}
