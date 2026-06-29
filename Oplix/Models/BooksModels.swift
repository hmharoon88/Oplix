//
//  BooksModels.swift
//  Oplix
//
//  Read-only models for web Daily books (Firestore `books` collection).
//

import Foundation

struct BooksShiftRegister: Equatable {
    var cardSale: Double
    var cashSale: Double
    var overShort: Double
}

struct BooksRegisterUnit: Equatable {
    var shift1: BooksShiftRegister
    var shift2: BooksShiftRegister
}

struct BooksGamingShift: Equatable {
    var cash: Double
    var overShort: Double
}

struct BooksFuelSale: Equatable {
    var gallons: Double
    var dollars: Double
    var regular: Double
    var midGrade: Double
    var premium: Double
    var diesel: Double
}

struct BooksLineItem: Equatable {
    var id: String
    var description: String
    var amount: Double
}

struct BooksPulltabEntry: Equatable {
    var id: String
    var ticketNumber: String
    var cash: Double
    var winner: Double
    var overShort: Double
}

struct BooksWindStationEntry: Equatable {
    var id: String
    var station: String
    var cash: Double
}

struct BooksKenoStationEntry: Equatable {
    var id: String
    var station: String
    var cash: Double
}

struct BooksLotteryUnit: Equatable {
    var shift1: BooksGamingShift
    var shift2: BooksGamingShift
}

struct BooksDayDoc: Equatable {
    var dayId: String
    var register1: BooksRegisterUnit
    var register2: BooksRegisterUnit
    var lottery: BooksLotteryUnit
    var pulltabs: [BooksPulltabEntry]
    var windStations: [BooksWindStationEntry]
    var kenoStations: [BooksKenoStationEntry]
    var fuelSale: BooksFuelSale
    var merchSale: Double
    var creditCard: Double
    var inHouseAccount: Double
    var waynePass: Double
    var lotteryPayOut: Double
    var pullTabPayout: Double
    var otherCashPayOut: Double
    var cashExpenses: [BooksLineItem]
    var checksAch: [BooksLineItem]
    var otherExpenses: [BooksLineItem]

    static func empty(dayId: String) -> BooksDayDoc {
        let emptyShift = BooksShiftRegister(cardSale: 0, cashSale: 0, overShort: 0)
        let emptyUnit = BooksRegisterUnit(shift1: emptyShift, shift2: emptyShift)
        let emptyGaming = BooksGamingShift(cash: 0, overShort: 0)
        return BooksDayDoc(
            dayId: dayId,
            register1: emptyUnit,
            register2: emptyUnit,
            lottery: BooksLotteryUnit(shift1: emptyGaming, shift2: emptyGaming),
            pulltabs: [],
            windStations: [],
            kenoStations: [],
            fuelSale: BooksFuelSale(gallons: 0, dollars: 0, regular: 0, midGrade: 0, premium: 0, diesel: 0),
            merchSale: 0,
            creditCard: 0,
            inHouseAccount: 0,
            waynePass: 0,
            lotteryPayOut: 0,
            pullTabPayout: 0,
            otherCashPayOut: 0,
            cashExpenses: [],
            checksAch: [],
            otherExpenses: []
        )
    }
}

/// Register / shift slot on the daily books sheet (matches web `register1.shift1`, etc.).
enum BooksRegisterSlot: CaseIterable, Equatable {
    case register1Shift1
    case register1Shift2
    case register2Shift1
    case register2Shift2

    var displayName: String {
        switch self {
        case .register1Shift1: return "Register 1 · Shift 1"
        case .register1Shift2: return "Register 1 · Shift 2"
        case .register2Shift1: return "Register 2 · Shift 1"
        case .register2Shift2: return "Register 2 · Shift 2"
        }
    }

    static func slot(at index: Int) -> BooksRegisterSlot? {
        guard index >= 0, index < allCases.count else { return nil }
        return allCases[index]
    }
}

extension BooksDayDoc {
    func shiftRegister(for slot: BooksRegisterSlot) -> BooksShiftRegister {
        switch slot {
        case .register1Shift1: return register1.shift1
        case .register1Shift2: return register1.shift2
        case .register2Shift1: return register2.shift1
        case .register2Shift2: return register2.shift2
        }
    }

    mutating func setShiftRegister(_ value: BooksShiftRegister, for slot: BooksRegisterSlot) {
        switch slot {
        case .register1Shift1: register1.shift1 = value
        case .register1Shift2: register1.shift2 = value
        case .register2Shift1: register2.shift1 = value
        case .register2Shift2: register2.shift2 = value
        }
    }
}

struct BooksPayrollWeeks: Equatable {
    var week1: Double
    var week2: Double
    var week3: Double
    var week4: Double
}

struct BooksPayrollLine: Equatable {
    var id: String
    var employeeName: String
    var pay: Double
}

struct BooksMonthDoc: Equatable {
    var utilities: [String: Double]
    var payroll: BooksPayrollWeeks
    var payrollLines: [BooksPayrollLine]
    var receivables: [BooksLineItem]
    var salesTax: Double
    var accountant: Double
}

struct BooksMonthPayload: Equatable {
    var monthId: String
    var month: BooksMonthDoc
    var daysById: [String: BooksDayDoc]
}

struct BooksDailySeriesPoint: Identifiable, Equatable {
    var id: String { dayId }
    let dayId: String
    let date: Date
    let sales: Double
    let expenses: Double
    let fuelGallons: Double
    let fuelDollars: Double
    let lotteryCash: Double
}

struct BooksMonthAggregate: Equatable {
    let monthId: String
    let sales: Double
    let lotteryCash: Double
    let payrollTotal: Double
    let expenses: Double
    let dailySeries: [BooksDailySeriesPoint]
}

enum BooksFirestoreParser {
    static func double(_ value: Any?) -> Double {
        if value == nil { return 0 }
        if let n = value as? Double { return n.isFinite ? n : 0 }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let n = Double(s.trimmingCharacters(in: .whitespaces)) {
            return n.isFinite ? n : 0
        }
        return 0
    }

    static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        return String(describing: value)
    }

    private static func shiftRegister(_ raw: Any?) -> BooksShiftRegister {
        let dict = raw as? [String: Any] ?? [:]
        return BooksShiftRegister(
            cardSale: double(dict["cardSale"]),
            cashSale: double(dict["cashSale"]),
            overShort: double(dict["overShort"])
        )
    }

    private static func registerUnit(_ raw: Any?) -> BooksRegisterUnit {
        let dict = raw as? [String: Any] ?? [:]
        return BooksRegisterUnit(
            shift1: shiftRegister(dict["shift1"]),
            shift2: shiftRegister(dict["shift2"])
        )
    }

    private static func gamingShift(_ raw: Any?) -> BooksGamingShift {
        let dict = raw as? [String: Any] ?? [:]
        return BooksGamingShift(
            cash: double(dict["cash"]),
            overShort: double(dict["overShort"])
        )
    }

    static func parseDay(dayId: String, data: [String: Any]) -> BooksDayDoc {
        let legacyRegister = data["register"] as? [String: Any]
        let register1 = registerUnit(data["register1"] ?? legacyRegister)
        let register2 = registerUnit(data["register2"])

        let lotteryRaw = data["lottery"] as? [String: Any] ?? [:]
        let lottery = BooksLotteryUnit(
            shift1: gamingShift(lotteryRaw["shift1"]),
            shift2: gamingShift(lotteryRaw["shift2"])
        )

        let pulltabs = parsePulltabs(data["pulltabs"], legacy: data["pulltab"])
        let windStations = parseWindStations(data["windStations"])
        let kenoStations = parseKenoStations(data["kenoStations"])

        let fuelRaw = data["fuelSale"] as? [String: Any] ?? [:]
        let fuel = BooksFuelSale(
            gallons: double(fuelRaw["gallons"]),
            dollars: double(fuelRaw["dollars"]),
            regular: double(fuelRaw["regular"]),
            midGrade: double(fuelRaw["midGrade"]),
            premium: double(fuelRaw["premium"]),
            diesel: double(fuelRaw["diesel"])
        )

        return BooksDayDoc(
            dayId: dayId,
            register1: register1,
            register2: register2,
            lottery: lottery,
            pulltabs: pulltabs,
            windStations: windStations,
            kenoStations: kenoStations,
            fuelSale: fuel,
            merchSale: double(data["merchSale"]),
            creditCard: double(data["creditCard"]),
            inHouseAccount: double(data["inHouseAccount"]),
            waynePass: double(data["waynePass"]),
            lotteryPayOut: {
                let parsed = double(data["lotteryPayOut"])
                if parsed != 0 { return parsed }
                return double(data["waynePassLotteryPayOut"])
            }(),
            pullTabPayout: double(data["pullTabPayout"]),
            otherCashPayOut: double(data["otherCashPayOut"]),
            cashExpenses: parseLineItems(data["cashExpenses"]),
            checksAch: parseLineItems(data["checksAch"]),
            otherExpenses: parseLineItems(data["otherExpenses"])
        )
    }

    static func parseMonth(data: [String: Any]) -> BooksMonthDoc {
        var utilities: [String: Double] = [:]
        if let utilRaw = data["utilities"] as? [String: Any] {
            for (key, value) in utilRaw {
                utilities[key] = double(value)
            }
        }

        let payrollRaw = data["payroll"] as? [String: Any] ?? [:]
        let payroll = BooksPayrollWeeks(
            week1: double(payrollRaw["week1"]),
            week2: double(payrollRaw["week2"]),
            week3: double(payrollRaw["week3"]),
            week4: double(payrollRaw["week4"])
        )

        let payrollLines = parsePayrollLines(data["payrollLines"])
        let receivables = parseLineItems(data["receivables"])

        return BooksMonthDoc(
            utilities: utilities,
            payroll: payroll,
            payrollLines: payrollLines,
            receivables: receivables,
            salesTax: double(data["salesTax"]),
            accountant: double(data["accountant"])
        )
    }

    private static func parseLineItems(_ raw: Any?) -> [BooksLineItem] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.enumerated().map { index, row in
            BooksLineItem(
                id: string(row["id"]).isEmpty ? "line_\(index)" : string(row["id"]),
                description: string(row["description"]),
                amount: double(row["amount"])
            )
        }
    }

    private static func parsePayrollLines(_ raw: Any?) -> [BooksPayrollLine] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.enumerated().map { index, row in
            BooksPayrollLine(
                id: string(row["id"]).isEmpty ? "pay_\(index)" : string(row["id"]),
                employeeName: string(row["employeeName"]),
                pay: double(row["pay"])
            )
        }
    }

    private static func parsePulltabs(_ raw: Any?, legacy: Any?) -> [BooksPulltabEntry] {
        if let rows = raw as? [[String: Any]], !rows.isEmpty {
            return rows.enumerated().map { index, row in
                BooksPulltabEntry(
                    id: string(row["id"]).isEmpty ? "pt_\(index)" : string(row["id"]),
                    ticketNumber: string(row["ticketNumber"]),
                    cash: double(row["cash"]),
                    winner: double(row["winner"]),
                    overShort: double(row["overShort"])
                )
            }
        }
        if let leg = legacy as? [String: Any] {
            let cash = double(leg["cash"])
            let winner = double(leg["winner"])
            let overShort = double(leg["overShort"])
            if cash != 0 || winner != 0 || overShort != 0 || !string(leg["ticketNumber"]).isEmpty {
                return [
                    BooksPulltabEntry(
                        id: "pt_legacy",
                        ticketNumber: string(leg["ticketNumber"]),
                        cash: cash,
                        winner: winner,
                        overShort: overShort
                    ),
                ]
            }
        }
        return []
    }

    private static func parseWindStations(_ raw: Any?) -> [BooksWindStationEntry] {
        guard let rows = raw as? [[String: Any]], !rows.isEmpty else { return [] }
        return rows.enumerated().map { index, row in
            BooksWindStationEntry(
                id: string(row["id"]).isEmpty ? "ws_\(index)" : string(row["id"]),
                station: string(row["station"]),
                cash: double(row["cash"])
            )
        }
    }

    private static func parseKenoStations(_ raw: Any?) -> [BooksKenoStationEntry] {
        guard let rows = raw as? [[String: Any]], !rows.isEmpty else { return [] }
        return rows.enumerated().map { index, row in
            BooksKenoStationEntry(
                id: string(row["id"]).isEmpty ? "ks_\(index)" : string(row["id"]),
                station: string(row["station"]),
                cash: double(row["cash"])
            )
        }
    }
}

enum BooksFirestoreEncoder {
    static func encodeShiftRegister(_ register: BooksShiftRegister) -> [String: Any] {
        [
            "cardSale": register.cardSale,
            "cashSale": register.cashSale,
            "overShort": register.overShort,
        ]
    }

    static func encodeRegisterUnit(_ unit: BooksRegisterUnit) -> [String: Any] {
        [
            "shift1": encodeShiftRegister(unit.shift1),
            "shift2": encodeShiftRegister(unit.shift2),
        ]
    }

    static func encodeGamingShift(_ shift: BooksGamingShift) -> [String: Any] {
        [
            "cash": shift.cash,
            "overShort": shift.overShort,
        ]
    }

    static func encodeLineItems(_ items: [BooksLineItem]) -> [[String: Any]] {
        items.map { item in
            [
                "id": item.id,
                "description": item.description,
                "amount": item.amount,
            ]
        }
    }

    static func encodePulltabs(_ items: [BooksPulltabEntry]) -> [[String: Any]] {
        items.map { item in
            [
                "id": item.id,
                "ticketNumber": item.ticketNumber,
                "cash": item.cash,
                "winner": item.winner,
                "overShort": item.overShort,
            ]
        }
    }

    static func encodeWindStations(_ items: [BooksWindStationEntry]) -> [[String: Any]] {
        items.map { item in
            [
                "id": item.id,
                "station": item.station,
                "cash": item.cash,
            ]
        }
    }

    static func encodeKenoStations(_ items: [BooksKenoStationEntry]) -> [[String: Any]] {
        items.map { item in
            [
                "id": item.id,
                "station": item.station,
                "cash": item.cash,
            ]
        }
    }

    static func encodeDay(_ day: BooksDayDoc) -> [String: Any] {
        [
            "register1": encodeRegisterUnit(day.register1),
            "register2": encodeRegisterUnit(day.register2),
            "lottery": [
                "shift1": encodeGamingShift(day.lottery.shift1),
                "shift2": encodeGamingShift(day.lottery.shift2),
            ],
            "pulltabs": encodePulltabs(day.pulltabs),
            "windStations": encodeWindStations(day.windStations),
            "kenoStations": encodeKenoStations(day.kenoStations),
            "fuelSale": [
                "gallons": day.fuelSale.gallons,
                "dollars": day.fuelSale.dollars,
                "regular": day.fuelSale.regular,
                "midGrade": day.fuelSale.midGrade,
                "premium": day.fuelSale.premium,
                "diesel": day.fuelSale.diesel,
            ],
            "merchSale": day.merchSale,
            "creditCard": day.creditCard,
            "inHouseAccount": day.inHouseAccount,
            "waynePass": day.waynePass,
            "lotteryPayOut": day.lotteryPayOut,
            "pullTabPayout": day.pullTabPayout,
            "otherCashPayOut": day.otherCashPayOut,
            "cashExpenses": encodeLineItems(day.cashExpenses),
            "checksAch": encodeLineItems(day.checksAch),
            "otherExpenses": encodeLineItems(day.otherExpenses),
        ]
    }

    static func defaultMonthPayload() -> [String: Any] {
        [
            "utilities": [:] as [String: Any],
            "payroll": [
                "week1": 0,
                "week2": 0,
                "week3": 0,
                "week4": 0,
            ],
            "payrollLines": [] as [[String: Any]],
            "receivables": [] as [[String: Any]],
            "salesTax": 0,
            "accountant": 0,
        ]
    }
}
