//
//  LotteryShiftCloseScanMatcherTests.swift
//  OplixTests
//

import XCTest
@testable import Oplix

final class LotteryShiftCloseScanMatcherTests: XCTestCase {

    private func row(
        id: String = UUID().uuidString,
        game: String = "696",
        packSerial: String? = "414265",
        beginning: String = "00",
        tickets: String = "25",
        value: String = "5",
        status: LotteryPackStatus? = .active
    ) -> LotteryFormTemplateRow {
        LotteryFormTemplateRow(
            id: id,
            gameNumber: game,
            value: value,
            tickets: tickets,
            beginningNumber: beginning,
            packSerial: packSerial,
            packStatus: status
        )
    }

    private func barcode(
        game: String = "696",
        serial: String = "414265",
        ticket: String = "014"
    ) -> OhioLotteryBarcode {
        OhioLotteryBarcode(
            raw: "\(game)-\(serial)-\(ticket)-8",
            gameNumber: game,
            packSerial: serial,
            ticketPosition: ticket,
            ticketNumber: OhioLotteryBarcodeParser.normalizeTicketPosition(ticket),
            checkDigit: "8",
            bookDigits: "\(game)\(serial)\(ticket)8".filter(\.isNumber)
        )
    }

    private func context(
        id: String = "a",
        bin: Int = 1,
        game: String = "696",
        packSerial: String? = "414265",
        beginning: String = "00",
        tickets: String = "25",
        value: String = "5"
    ) -> LotteryShiftCloseScanMatcher.RowContext {
        LotteryShiftCloseScanMatcher.RowContext(
            id: id,
            binNumber: bin,
            gameNumber: game,
            packSerial: packSerial,
            beginningNumber: beginning,
            tickets: tickets,
            value: value
        )
    }

    func testScannableRowsSkipsEmptyBins() {
        let rows = [
            row(beginning: "00"),
            row(game: "1091", beginning: "")
        ]
        let scannable = LotteryShiftCloseScanMatcher.scannableRows(from: rows)
        XCTAssertEqual(scannable.count, 1)
    }

    func testMatchByPackSerial() throws {
        let id = "bin-3"
        let rows = [
            row(id: "bin-1", packSerial: "111111"),
            row(id: id, packSerial: "414265")
        ]
        let contexts = LotteryShiftCloseScanMatcher.scannableRows(from: rows)
        let matched = try XCTUnwrap(
            LotteryShiftCloseScanMatcher.match(barcode: barcode(), rows: contexts).matched
        )
        XCTAssertEqual(matched.id, id)
    }

    func testMatchWrongPackSerialSameGameIsUnrecognized() {
        let rows = [row(packSerial: "999999")]
        let contexts = LotteryShiftCloseScanMatcher.scannableRows(from: rows)
        let result = LotteryShiftCloseScanMatcher.match(barcode: barcode(), rows: contexts)
        guard case .unrecognizedPack(let scanned, let candidates) = result else {
            return XCTFail("Expected unrecognizedPack, got \(result)")
        }
        XCTAssertEqual(scanned.packSerial, "414265")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].packSerial, "999999")
    }

    func testBrandNewGameOffersOccupiedBinsToReplace() {
        let rows = [
            row(id: "bin-1", game: "696", packSerial: "111111"),
            row(id: "bin-2", game: "1091", packSerial: "222222")
        ]
        let contexts = LotteryShiftCloseScanMatcher.scannableRows(from: rows)
        let result = LotteryShiftCloseScanMatcher.match(
            barcode: barcode(game: "1200", serial: "333333", ticket: "000"),
            rows: contexts
        )
        guard case .unrecognizedPack(let scanned, let candidates) = result else {
            return XCTFail("Expected unrecognizedPack for new game, got \(result)")
        }
        XCTAssertEqual(scanned.gameNumber, "1200")
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(Set(candidates.map(\.id)), Set(["bin-1", "bin-2"]))
    }

    func testEndingNumberFromOpenTicket() throws {
        let ending = try XCTUnwrap(
            LotteryShiftCloseScanMatcher.endingNumber(from: barcode(ticket: "014"), row: context()).success
        )
        XCTAssertEqual(ending, "14")
    }

    func testRejectsSealedPackWhenBookWasOpened() {
        let result = LotteryShiftCloseScanMatcher.endingNumber(
            from: barcode(ticket: "000"),
            row: context(beginning: "05")
        )
        XCTAssertTrue(result.failure?.localizedDescription.contains("sealed pack") == true)
    }

    func testAutoSeamlessTargetWhenOneSameGameBin() {
        let candidates = [
            context(id: "a", bin: 1, game: "696", packSerial: "111111"),
            context(id: "b", bin: 2, game: "1091", packSerial: "222222")
        ]
        let target = LotteryShiftCloseScanMatcher.autoSeamlessTarget(
            for: barcode(game: "696", serial: "999999", ticket: "014"),
            among: candidates
        )
        XCTAssertEqual(target?.id, "a")
    }

    func testAutoSeamlessTargetNilWhenMultipleSameGameBins() {
        let candidates = [
            context(id: "a", bin: 1, game: "696", packSerial: "111111"),
            context(id: "b", bin: 2, game: "696", packSerial: "222222")
        ]
        let target = LotteryShiftCloseScanMatcher.autoSeamlessTarget(
            for: barcode(game: "696", serial: "999999", ticket: "014"),
            among: candidates
        )
        XCTAssertNil(target)
    }

    func testAutoSeamlessTargetNilForDifferentGameOnly() {
        let candidates = [
            context(id: "a", bin: 1, game: "1091", packSerial: "111111")
        ]
        let target = LotteryShiftCloseScanMatcher.autoSeamlessTarget(
            for: barcode(game: "696", serial: "999999", ticket: "014"),
            among: candidates
        )
        XCTAssertNil(target)
    }
}

private extension LotteryShiftCloseScanMatcher.MatchOutcome {
    var matched: LotteryShiftCloseScanMatcher.RowContext? {
        if case .matched(let row) = self { return row }
        return nil
    }
}

private extension Result where Failure == LotteryShiftCloseScanMatcher.ScanError {
    var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
