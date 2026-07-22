//
//  LotteryBeginVerificationTests.swift
//  OplixTests
//
//  Regression tests for the stale-Begin detection that runs at shift
//  close. The first tests replay the real Fast Mart 7/16 incident:
//  a device frozen since the 7/15 morning close submitted Begins that
//  skipped the 7/15 evening close, double-counting the evening
//  shift's sales and producing a false −$494 short.
//

import XCTest
@testable import Oplix

final class LotteryBeginVerificationTests: XCTestCase {

    private func form(id: String, minutesAgo: Double, ends: [String: String]) -> LotteryForm {
        var formData: [String: String] = [:]
        for (rowId, end) in ends {
            formData["row_\(rowId)"] = end
        }
        return LotteryForm(
            id: id,
            locationId: "loc",
            shiftId: "shift-\(id)",
            formData: formData,
            notes: "",
            submittedAt: Date(timeIntervalSinceNow: -minutesAgo * 60)
        )
    }

    private func row(
        _ id: String,
        game: String,
        begin: String,
        value: String = "5",
        tickets: String = "50"
    ) -> LotteryFormTemplateRow {
        LotteryFormTemplateRow(
            id: id,
            binNumber: "1",
            gameNumber: game,
            value: value,
            tickets: tickets,
            beginningNumber: begin
        )
    }

    // MARK: - Fast Mart 7/16 regression

    /// Game 1035 ($5, 50 tickets): morning close ended at 15, evening
    /// close ended at 21, night device still held Begin 15 → must be
    /// corrected to 21.
    func testFastMartStaleBeginIsCorrected() {
        let forms = [
            form(id: "evening", minutesAgo: 60, ends: ["r1035": "21", "r1040": "44"]),
            form(id: "morning", minutesAgo: 16 * 60, ends: ["r1035": "15", "r1040": "36"]),
        ]
        let rows = [
            row("r1035", game: "1035", begin: "15"),
            row("r1040", game: "1040", begin: "36", value: "2", tickets: "100"),
        ]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )

        XCTAssertEqual(corrections.count, 2)
        XCTAssertEqual(corrections.first(where: { $0.rowId == "r1035" })?.newBegin, "21")
        XCTAssertEqual(corrections.first(where: { $0.rowId == "r1040" })?.newBegin, "44")
    }

    /// Begins that correctly continue from the latest close are untouched.
    func testCorrectBeginsPassVerification() {
        let forms = [
            form(id: "evening", minutesAgo: 60, ends: ["r1": "21"]),
            form(id: "morning", minutesAgo: 16 * 60, ends: ["r1": "15"]),
        ]
        let rows = [row("r1", game: "1035", begin: "21")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    // MARK: - Legitimate Begin changes are never "corrected"

    /// A pack replaced between closes starts at a scanned position that
    /// matches no older close's End — left alone even though it
    /// disagrees with the latest End.
    func testReplacedPackBeginIsLeftAlone() {
        let forms = [
            form(id: "last", minutesAgo: 60, ends: ["r1": "21"]),
            form(id: "older", minutesAgo: 16 * 60, ends: ["r1": "15"]),
        ]
        let rows = [row("r1", game: "1099", begin: "7")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    /// A fresh sealed pack begins at 00 — never corrected, even when
    /// some old close on this bin also ended at 00.
    func testSealedPackBeginIsLeftAloneForwardOrder() {
        let forms = [
            form(id: "last", minutesAgo: 60, ends: ["r1": "12"]),
            form(id: "older", minutesAgo: 16 * 60, ends: ["r1": "00"]),
        ]
        let rows = [row("r1", game: "1050", begin: "00")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    /// Reverse-order facilities: sealed Begin is tickets-1 (e.g. 49).
    func testSealedPackBeginIsLeftAloneReverseOrder() {
        let forms = [
            form(id: "last", minutesAgo: 60, ends: ["r1": "30"]),
            form(id: "older", minutesAgo: 16 * 60, ends: ["r1": "49"]),
        ]
        let rows = [row("r1", game: "1050", begin: "49", tickets: "50")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: true,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    // MARK: - Edge cases

    /// "0" and "00" are the same ticket position.
    func testZeroNormalization() {
        XCTAssertEqual(LotteryBeginVerificationService.normalized("0"), "00")
        XCTAssertEqual(LotteryBeginVerificationService.normalized(" 00 "), "00")
        XCTAssertEqual(LotteryBeginVerificationService.normalized("15"), "15")
    }

    /// No previous closes → nothing to verify against.
    func testNoHistoryMeansNoCorrections() {
        let lookups = LotteryBeginVerificationService.endLookups(forms: [])
        let corrections = LotteryBeginVerificationService.corrections(
            rows: [row("r1", game: "1035", begin: "15")],
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    /// Only one close on record → begins can't match an "older" close,
    /// so mismatches are treated as legitimate (pack changes).
    func testSingleCloseHistoryNeverCorrects() {
        let forms = [form(id: "only", minutesAgo: 60, ends: ["r1": "21"])]
        let rows = [row("r1", game: "1035", begin: "15")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    /// Rows the last close never filled in (empty End) are skipped.
    func testEmptyLastEndIsSkipped() {
        let forms = [
            form(id: "last", minutesAgo: 60, ends: ["r1": ""]),
            form(id: "older", minutesAgo: 16 * 60, ends: ["r1": "15"]),
        ]
        let rows = [row("r1", game: "1035", begin: "15")]

        let lookups = LotteryBeginVerificationService.endLookups(forms: forms)
        let corrections = LotteryBeginVerificationService.corrections(
            rows: rows,
            reverseOrder: false,
            lastCloseEnds: lookups.last,
            olderEnds: lookups.older
        )
        XCTAssertTrue(corrections.isEmpty)
    }

    /// Alert message lists the corrections and caps the row detail.
    func testAlertMessageContainsCorrections() {
        let corrections = [
            LotteryBeginCorrection(rowId: "r1", binNumber: "3", gameNumber: "1035", oldBegin: "15", newBegin: "21"),
        ]
        let message = LotteryBeginVerificationService.alertMessage(for: corrections)
        XCTAssertTrue(message.contains("Game 1035"))
        XCTAssertTrue(message.contains("15 → 21"))
    }
}
