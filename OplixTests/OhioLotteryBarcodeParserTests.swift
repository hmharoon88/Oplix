//
//  OhioLotteryBarcodeParserTests.swift
//  OplixTests
//

import Testing
@testable import Oplix

struct OhioLotteryBarcodeParserTests {

    @Test func parsesDashedPackBarcode() throws {
        let result = OhioLotteryBarcodeParser.parse("1091-0017360-000-2")
        let barcode = try #require(try result.get())

        #expect(barcode.gameNumber == "1091")
        #expect(barcode.packSerial == "0017360")
        #expect(barcode.ticketPosition == "000")
        #expect(barcode.ticketNumber == "00")
        #expect(barcode.checkDigit == "2")
        #expect(barcode.isSealedPack)
    }

    @Test func parsesAdditionalPhotoSamples() throws {
        let samples: [(String, String)] = [
            ("1091-0017332-000-6", "0017332"),
            ("1091-0017374-000-4", "0017374"),
        ]

        for (raw, pack) in samples {
            let barcode = try OhioLotteryBarcodeParser.parse(raw).get()
            #expect(barcode.gameNumber == "1091")
            #expect(barcode.packSerial == pack)
            #expect(barcode.isSealedPack)
        }
    }

    @Test func parsesCompactBarcode() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("109100173600002").get()
        #expect(barcode.gameNumber == "1091")
        #expect(barcode.packSerial == "0017360")
        #expect(barcode.ticketNumber == "00")
    }

    @Test func normalizesOpenTicketPosition() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("1091-0017360-014-2").get()
        #expect(barcode.ticketPosition == "014")
        #expect(barcode.ticketNumber == "14")
        #expect(!barcode.isSealedPack)
    }

    @Test func normalizeTicketPositionHelper() {
        #expect(OhioLotteryBarcodeParser.normalizeTicketPosition("000") == "00")
        #expect(OhioLotteryBarcodeParser.normalizeTicketPosition("014") == "14")
        #expect(OhioLotteryBarcodeParser.normalizeTicketPosition("024") == "24")
    }

    @Test func rejectsEmptyAndMalformed() {
        #expect(OhioLotteryBarcodeParser.parse("").error == .empty)
        #expect(OhioLotteryBarcodeParser.parse("1091-0017360").error == .invalidFormat)
        #expect(OhioLotteryBarcodeParser.parse("abcd-efgh").error == .invalidFormat)
    }

    @Test func rejectsTicketFaceUpc() {
        // UPC-A on ticket face: 6 70656 30696 4
        #expect(OhioLotteryBarcodeParser.parse("670656306964").error == .notLotteryBarcode)
        #expect(OhioLotteryBarcodeParser.parse("0670656306964").error == .notLotteryBarcode)
        #expect(!OhioLotteryBarcodeParser.isLikelyOhioLotteryBarcode("0670656306964"))
    }

    @Test func rejectsShippingCaseLabelBarcode() {
        // Structure may parse, but game 3785 isn't a known Ohio game in the DB check layer.
        let parsed = OhioLotteryBarcodeParser.parse("37853101135785")
        if case .success(let barcode) = parsed {
            #expect(!OhioLotteryBarcodeParser.isKnownGame(barcode.gameNumber, knownGames: ["696", "1091"]))
        }
    }

    @Test func rejectsUpcAndUrls() {
        #expect(OhioLotteryBarcodeParser.parse("123456789012").error == .notLotteryBarcode)
        #expect(OhioLotteryBarcodeParser.parse("https://ohiolottery.com").error == .notLotteryBarcode)
        #expect(!OhioLotteryBarcodeParser.isLikelyOhioLotteryBarcode("123456789012"))
    }

    @Test func isLikelyOhioLotteryBarcode() {
        #expect(OhioLotteryBarcodeParser.isLikelyOhioLotteryBarcode(" 1091-0017360-000-2 "))
        #expect(!OhioLotteryBarcodeParser.isLikelyOhioLotteryBarcode("not a code"))
    }

    @Test func preprocessCompactDigits() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("109100173600002").get()
        #expect(barcode.packSerial == "0017360")
    }

    @Test func parsesThreeDigitGameRetailScan() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("696414265002805979").get()
        #expect(barcode.gameNumber == "696")
        #expect(barcode.packSerial == "0414265")
        #expect(barcode.ticketPosition == "002")
        #expect(barcode.checkDigit == "8")
    }

    @Test func parsesThreeDigitGameDashedLabel() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("696-414265-002-8").get()
        #expect(barcode.gameNumber == "696")
        #expect(barcode.packSerial == "0414265")
    }

    @Test func parsesTerminalPaddedFourDigitGameDashed() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("0696-414265-002-8").get()
        #expect(barcode.gameNumber == "696")
        #expect(barcode.packSerial == "0414265")
        #expect(barcode.ticketPosition == "002")
    }

    @Test func parsesTerminalPaddedCompactScan() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("0696414265002805979").get()
        #expect(barcode.gameNumber == "696")
        #expect(barcode.packSerial == "0414265")
        #expect(barcode.checkDigit == "8")
    }

    @Test func parsesFourDigitGameLongTerminalScan() throws {
        // Printed label on pack: 1086-0167066-004-9. Terminal scan string from photo.
        let barcode = try OhioLotteryBarcodeParser.parse("10860167066005108908").get()
        #expect(barcode.gameNumber == "1086")
        #expect(barcode.packSerial == "0167066")
        #expect(barcode.ticketPosition == "005")
        #expect(barcode.ticketNumber == "5")
        #expect(barcode.checkDigit == "1")
        #expect(!barcode.isSealedPack)
    }

    @Test func parsesFourDigitGameLongScanMatchingPrintedLabel() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("108601670660049108908").get()
        #expect(barcode.gameNumber == "1086")
        #expect(barcode.packSerial == "0167066")
        #expect(barcode.ticketPosition == "004")
        #expect(barcode.ticketNumber == "4")
        #expect(barcode.checkDigit == "9")
        #expect(barcode.dashedLabel == "1086-0167066-004-9")
        #expect(barcode.extraScannerDigitCount == 6)
    }

    @Test func dashedLabelMatchesPrintedTextAboveBarcode() throws {
        let barcode = try OhioLotteryBarcodeParser.parse("696414265002805979").get()
        #expect(barcode.dashedLabel == "696-414265-002-8")
        #expect(barcode.extraScannerDigitCount == 5)
        #expect(barcode.bookDigits == "6964142650028")
    }

    @Test func gameLookupCandidatesIncludesZeroPadded() {
        let candidates = OhioLotteryBarcodeParser.gameLookupCandidates("696")
        #expect(candidates.contains("696"))
        #expect(candidates.contains("0696"))
    }

    @Test func canonicalGameNumberStripsLeadingZeros() {
        #expect(OhioLotteryBarcodeParser.canonicalGameNumber("696") == "696")
        #expect(OhioLotteryBarcodeParser.canonicalGameNumber("0696") == "696")
        #expect(OhioLotteryBarcodeParser.canonicalGameNumber("1091") == "1091")
    }

    @Test func isKnownGameUsesDatabaseNumbers() {
        let known: Set<String> = ["696", "1091"]
        #expect(OhioLotteryBarcodeParser.isKnownGame("696", knownGames: known))
        #expect(OhioLotteryBarcodeParser.isKnownGame("0696", knownGames: known))
        #expect(!OhioLotteryBarcodeParser.isKnownGame("3785", knownGames: known))
    }

    @Test func gameNumbersMatchZeroPadded() {
        #expect(OhioLotteryBarcodeParser.gameNumbersMatch("696", "0696"))
        #expect(OhioLotteryBarcodeParser.gameNumbersMatch("1091", "1091"))
        #expect(!OhioLotteryBarcodeParser.gameNumbersMatch("696", "697"))
    }

    @Test func crossCheckPrintedLabelVerified() throws {
        let scanned = try OhioLotteryBarcodeParser.parse("696414265002805979").get()
        let result = OhioLotteryBarcodeParser.crossCheckPrintedLabel(
            barcode: scanned,
            ocrTexts: ["696-414265-002-8", "Ohio Lottery"]
        )
        #expect(result == .verified)
    }

    @Test func crossCheckPrintedLabelMismatch() throws {
        let scanned = try OhioLotteryBarcodeParser.parse("109100173600002").get()
        let result = OhioLotteryBarcodeParser.crossCheckPrintedLabel(
            barcode: scanned,
            ocrTexts: ["696-414265-002-8"]
        )
        #expect(result == .mismatch(printed: "696-414265-002-8"))
    }

    @Test func crossCheckPrintedLabelNoOCR() throws {
        let scanned = try OhioLotteryBarcodeParser.parse("109100173600002").get()
        let result = OhioLotteryBarcodeParser.crossCheckPrintedLabel(
            barcode: scanned,
            ocrTexts: ["PLEASE PLAY RESPONSIBLY"]
        )
        #expect(result == .noPrintedVisible)
    }
}

private extension Result where Failure == OhioLotteryBarcodeParser.ParseError {
    var error: OhioLotteryBarcodeParser.ParseError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
