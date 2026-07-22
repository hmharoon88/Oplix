//
//  LotteryPackInventoryViewModel.swift
//  Oplix
//

import Foundation

struct LotteryPackRackRow: Identifiable, Equatable {
    let id: String
    let binNumber: String
    let gameNumber: String
    let value: String
    let tickets: String
    let packSerial: String?
    let packStatus: LotteryPackStatus?
    let beginningNumber: String
    let terminalNumber: Int

    var statusLabel: String {
        switch packStatus {
        case .active: return "Active"
        case .returned: return "Returned"
        case .empty: return "Empty"
        case nil:
            return packSerial?.isEmpty == false ? "Active" : "No pack"
        }
    }

    var hasActivePack: Bool {
        guard let serial = packSerial, !serial.isEmpty else { return false }
        switch packStatus {
        case .active: return true
        case .returned, .empty: return false
        case nil: return true
        }
    }

    /// Any pack serial still stored on the bin (including odd leftover statuses).
    var hasPackSerialOnBin: Bool {
        guard let serial = packSerial, !serial.isEmpty else { return false }
        return true
    }

    /// Bin has rack data that assigning would overwrite (pack and/or Begin #).
    var looksOccupiedForAssign: Bool {
        if hasPackSerialOnBin { return true }
        return !beginningNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// What happens if a scanned pack is placed on a bin row.
enum PackBinAssignSituation: Equatable {
    case currentLocation
    case empty
    /// Another pack of the same game is already on this bin (different pack serial).
    case replaceSameGame(existingSerial: String)
    case replaceDifferentGame(existingGame: String, existingSerial: String)
}

enum LotteryPackAssignError: LocalizedError {
    case invalidBarcode(String)
    case gameNotInDatabase(String)
    case newGameMissingDetails
    case newGameMustBeSealedPack
    case noMatchingBin
    case templateSaveFailed(String)
    case packNotFound
    case packNotActive
    case destinationBinOccupied
    case returnSaveFailed(String)
    case gameSaveFailed(String)
    case alreadyInStock
    case alreadyOnRack
    case stockSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode(let msg): return msg
        case .gameNotInDatabase(let game): return "Game \(game) isn't in the game database. Enter the ticket value below."
        case .newGameMissingDetails: return "Enter the ticket value for this new game (tickets per pack are filled from your database when possible)."
        case .newGameMustBeSealedPack: return "New games should be added from a sealed pack (Begin # 00 on the barcode). Confirm below if this pack is already open."
        case .noMatchingBin: return "No bin available for this pack. Add a row in lottery customization first."
        case .templateSaveFailed(let msg): return msg
        case .packNotFound: return "No active pack with that serial on this terminal."
        case .packNotActive: return "That pack isn't active on the rack."
        case .destinationBinOccupied: return "That bin already has a pack. Move it somewhere empty, or return/replace first."
        case .returnSaveFailed(let msg): return msg
        case .gameSaveFailed(let msg): return msg
        case .alreadyInStock: return "That pack is already in stock."
        case .alreadyOnRack: return "That pack is already on a bin. Use Move if you need to relocate it."
        case .stockSaveFailed(let msg): return msg
        }
    }
}

@MainActor
final class LotteryPackInventoryViewModel: ObservableObject {
    @Published var rackRows: [LotteryPackRackRow] = []
    @Published var stockPacks: [LotteryStockPack] = []
    @Published var pendingReturns: [LotteryReturn] = []
    @Published var recentReturns: [LotteryReturn] = []
    @Published var pendingCloseouts: [LotteryPackCloseout] = []
    @Published var selectedTerminal: Int = 1
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let managerUserId: String
    let location: Location

    private let firebaseService = FirebaseService.shared
    private var templatesByTerminal: [Int: LotteryFormTemplate] = [:]
    private var gameDatabase: [GameData] = []

    /// Canonical game numbers from the global game database (no leading zeros).
    var knownGameNumbers: Set<String> {
        Set(gameDatabase.map { OhioLotteryBarcodeParser.canonicalGameNumber($0.gameNumber) })
    }

    func isKnownGame(_ gameNumber: String) -> Bool {
        OhioLotteryBarcodeParser.isKnownGame(gameNumber, knownGames: knownGameNumbers)
    }

    /// Tickets-per-pack for a new game value, using catalog majority then Ohio defaults.
    func suggestedTickets(forNewGameValue value: String) -> String? {
        LotteryGameTicketDefaults.suggestedTickets(value: value, from: gameDatabase)
    }

    func newGameSuggestionUsesCatalog(value: String) -> Bool {
        LotteryGameTicketDefaults.suggestionUsesCatalog(value: value, from: gameDatabase)
    }

    init(managerUserId: String, location: Location) {
        self.managerUserId = managerUserId
        self.location = location
        self.selectedTerminal = 1
    }

    var terminalNumbers: [Int] {
        location.activeLotteryTerminalNumbers
    }

    var hasMultipleTerminals: Bool {
        location.hasMultipleLotteryTerminals
    }

    func reverseOrder(for terminal: Int) -> Bool {
        templatesByTerminal[terminal]?.reverseOrder ?? false
    }

    var emptyBinRows: [LotteryPackRackRow] {
        allBinRows().filter { !$0.hasActivePack }
    }

    /// Re-pull the selected terminal's template from the server right
    /// before mutating it. The rack screen can sit open (or frozen in
    /// the background) for a long time; mutating and saving the copy
    /// loaded at open time would overwrite anything other devices
    /// changed since — same stale-data bug as the shift close.
    private func refreshSelectedTemplateFromServer() async {
        if let fresh = try? await firebaseService.fetchLotteryFormTemplate(
            userId: managerUserId,
            locationId: location.id,
            terminalNumber: selectedTerminal,
            source: .server
        ) {
            templatesByTerminal[selectedTerminal] = fresh
            rebuildRackRows()
        }
    }

    /// Move an existing pack to an empty bin — no sales or return math.
    func movePack(fromRowId: String, toRowId: String) async throws {
        await refreshSelectedTemplateFromServer()
        guard var template = templatesByTerminal[selectedTerminal] else {
            throw LotteryPackAssignError.noMatchingBin
        }
        guard let fromIndex = template.rows.firstIndex(where: { $0.id == fromRowId }),
              let toIndex = template.rows.firstIndex(where: { $0.id == toRowId }) else {
            throw LotteryPackAssignError.noMatchingBin
        }
        guard fromIndex != toIndex else { return }

        let source = template.rows[fromIndex]
        guard rowHasActivePack(source), let serial = source.packSerial, !serial.isEmpty else {
            throw LotteryPackAssignError.packNotActive
        }
        guard !rowHasActivePack(template.rows[toIndex]) else {
            throw LotteryPackAssignError.destinationBinOccupied
        }

        template.rows[toIndex].gameNumber = source.gameNumber
        template.rows[toIndex].value = source.value
        template.rows[toIndex].tickets = source.tickets
        template.rows[toIndex].packSerial = source.packSerial
        template.rows[toIndex].packStatus = source.packStatus ?? .active
        template.rows[toIndex].beginningNumber = source.beginningNumber
        template.rows[toIndex].endingNumber = source.endingNumber
        template.rows[toIndex].sold = source.sold
        template.rows[toIndex].dollar = source.dollar
        template.rows[toIndex].books = source.books

        clearBinRow(&template.rows[fromIndex])

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            try await firebaseService.saveLotteryFormTemplate(
                userId: managerUserId,
                locationId: location.id,
                template: template
            )
            templatesByTerminal[selectedTerminal] = template
            rebuildRackRows()
            let fromBin = displayBinNumber(for: source, at: fromIndex)
            let toBin = displayBinNumber(for: template.rows[toIndex], at: toIndex)
            successMessage = "Moved pack \(serial) from bin \(fromBin) to bin \(toBin) (no sales change)."
        } catch {
            throw LotteryPackAssignError.templateSaveFailed(error.localizedDescription)
        }
    }

    var pendingReturnDollars: Double {
        pendingReturns.reduce(0) { $0 + $1.returnedDollars }
    }

    var pendingReturnCloseDeductionDollars: Double {
        pendingReturns.reduce(0) { $0 + $1.closeDeductionDollars }
    }

    var pendingCloseoutDollars: Double {
        pendingCloseouts.reduce(0) { $0 + $1.soldDollars }
    }

    var pendingCloseoutTickets: Int {
        pendingCloseouts.reduce(0) { $0 + $1.soldTickets }
    }

    /// Applied returns in recent history (rack audit).
    var tallyReturnedPacks: Int {
        appliedReturnHistory.count
    }

    var tallyReturnedDollars: Double {
        appliedReturnHistory.reduce(0) { $0 + $1.returnedDollars }
    }

    /// Finished/sold packs waiting to credit at next close.
    var tallySoldFinishedPacks: Int {
        pendingCloseouts.count
    }

    var tallySoldFinishedDollars: Double {
        pendingCloseoutDollars
    }


    /// Bins with an active pack on the current terminal (for manual return without barcode).
    var activePackRows: [LotteryPackRackRow] {
        rackRows.filter { row in
            guard let serial = row.packSerial, !serial.isEmpty else { return false }
            switch row.packStatus {
            case .active: return true
            case .returned, .empty: return false
            case nil: return true
            }
        }
    }

    /// Preview return $ before confirming (scan or manual).
    func returnPreview(rowId: String, fromTicket: String) -> (tickets: Int, dollars: Double)? {
        guard let template = templatesByTerminal[selectedTerminal],
              let index = template.rows.firstIndex(where: { $0.id == rowId }) else { return nil }
        let row = template.rows[index]
        guard rowHasActivePack(row) else { return nil }

        let ticket = normalizedReturnTicket(fromTicket)
        guard !ticket.isEmpty else { return nil }
        let isSealed = ticket == "00"

        let returnedTickets = LotteryCalculationService.calculateReturnedTickets(
            fromTicket: ticket,
            ticketsInBook: row.tickets,
            reverseOrder: template.reverseOrder,
            isSealedPack: isSealed
        )
        let returnedDollars = Double(
            LotteryCalculationService.calculateDollars(sold: returnedTickets, value: row.value)
        )
        return (returnedTickets, returnedDollars)
    }

    func loadRack() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let templatesTask = firebaseService.fetchAllLotteryFormTemplates(
                userId: managerUserId,
                locationId: location.id
            )
            async let returnsTask = firebaseService.fetchPendingLotteryReturns(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            async let recentReturnsTask = firebaseService.fetchRecentLotteryReturns(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            async let closeoutsTask = firebaseService.fetchPendingLotteryPackCloseouts(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            async let gamesTask = firebaseService.fetchAllGameData()
            async let stockTask = firebaseService.fetchInStockLotteryPacks(
                userId: managerUserId,
                locationId: location.id
            )
            let templates = try await templatesTask
            templatesByTerminal = Dictionary(
                uniqueKeysWithValues: templates.map { ($0.effectiveTerminalNumber, $0) }
            )
            pendingReturns = try await returnsTask
            recentReturns = try await recentReturnsTask
            pendingCloseouts = try await closeoutsTask
            gameDatabase = try await gamesTask
            stockPacks = try await stockTask
            rebuildRackRows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTerminal(_ terminal: Int) {
        selectedTerminal = terminal
        rebuildRackRows()
        Task { await reloadPendingReturns() }
    }

    private func reloadPendingReturns() async {
        do {
            async let returnsTask = firebaseService.fetchPendingLotteryReturns(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            async let recentReturnsTask = firebaseService.fetchRecentLotteryReturns(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            async let closeoutsTask = firebaseService.fetchPendingLotteryPackCloseouts(
                userId: managerUserId,
                locationId: location.id,
                terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
            )
            pendingReturns = try await returnsTask
            recentReturns = try await recentReturnsTask
            pendingCloseouts = try await closeoutsTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var pendingReturnLineItems: [LotteryPackReturnLineItem] {
        pendingReturns.map { LotteryPackReturnLineItem(from: $0, ticketValue: $0.resolvedTicketValue) }
    }

    var appliedReturnHistory: [LotteryReturn] {
        recentReturns.filter { $0.status == .applied }
    }

    /// Bin that currently holds this pack serial, if any.
    func rowHoldingPack(serial: String) -> LotteryPackRackRow? {
        guard let template = templatesByTerminal[selectedTerminal],
              let row = template.rows.first(where: {
                  OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, serial)
              }) else { return nil }
        return rackRow(from: row, terminal: selectedTerminal, in: template)
    }

    /// Any terminal that currently holds this pack serial.
    func rowHoldingPackAnywhere(serial: String) -> LotteryPackRackRow? {
        for (terminal, template) in templatesByTerminal {
            if let row = template.rows.first(where: {
                OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, serial)
            }) {
                return rackRow(from: row, terminal: terminal, in: template)
            }
        }
        return nil
    }

    func stockPack(matchingSerial serial: String) -> LotteryStockPack? {
        stockPacks.first {
            OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, serial)
        }
    }

    /// Receive a pack into location stock (not on a bin yet).
    func receiveStockPack(
        barcodeRaw: String,
        newGameValue: String? = nil,
        newGameTickets: String? = nil,
        confirmOpenPackForNewGame: Bool = false
    ) async throws {
        let parseResult = OhioLotteryBarcodeParser.parse(barcodeRaw)
        guard case .success(let barcode) = parseResult else {
            if case .failure(let error) = parseResult {
                throw LotteryPackAssignError.invalidBarcode(userMessage(for: error))
            }
            throw LotteryPackAssignError.invalidBarcode("Not a valid Ohio lottery barcode.")
        }

        if rowHoldingPackAnywhere(serial: barcode.packSerial) != nil {
            throw LotteryPackAssignError.alreadyOnRack
        }
        if stockPack(matchingSerial: barcode.packSerial) != nil {
            throw LotteryPackAssignError.alreadyInStock
        }

        let gameData: GameData
        if isKnownGame(barcode.gameNumber) {
            guard let resolved = try await resolveGameData(gameNumber: barcode.gameNumber) else {
                throw LotteryPackAssignError.gameNotInDatabase(barcode.gameNumber)
            }
            gameData = resolved
        } else {
            let value = LotteryGameTicketDefaults.normalizeValue(newGameValue ?? "")
            let tickets = LotteryGameTicketDefaults.normalizeTickets(newGameTickets ?? "") ?? ""
            guard !value.isEmpty, !tickets.isEmpty else {
                throw LotteryPackAssignError.newGameMissingDetails
            }
            if !barcode.isSealedPack && !confirmOpenPackForNewGame {
                throw LotteryPackAssignError.newGameMustBeSealedPack
            }
            gameData = try await addGameToDatabase(
                gameNumber: barcode.gameNumber,
                value: value,
                tickets: tickets
            )
        }

        let pack = LotteryStockPack(
            locationId: location.id,
            gameNumber: OhioLotteryBarcodeParser.canonicalGameNumber(gameData.gameNumber),
            packSerial: barcode.packSerial,
            value: gameData.value,
            tickets: gameData.tickets,
            receivedTicketNumber: barcode.ticketNumber.isEmpty ? "00" : barcode.ticketNumber
        )

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            try await firebaseService.createLotteryStockPack(
                userId: managerUserId,
                locationId: location.id,
                pack: pack
            )
            stockPacks.append(pack)
            stockPacks.sort { lhs, rhs in
                let gameCmp = lhs.gameNumber.localizedStandardCompare(rhs.gameNumber)
                if gameCmp != .orderedSame { return gameCmp == .orderedAscending }
                return lhs.packSerial.localizedStandardCompare(rhs.packSerial) == .orderedAscending
            }
            successMessage = "Pack \(barcode.packSerial) (Game \(pack.gameNumber)) received into stock."
        } catch {
            throw LotteryPackAssignError.stockSaveFailed(error.localizedDescription)
        }
    }

    /// Assign an in-stock pack onto a bin (same rules as scanning assign).
    func assignStockPack(_ pack: LotteryStockPack, toRowId rowId: String) async throws {
        let ticket = pack.receivedTicketNumber.isEmpty ? "00" : pack.receivedTicketNumber
        let paddedTicket: String = {
            if ticket == "00" || ticket == "0" { return "000" }
            if let n = Int(ticket) { return String(format: "%03d", n) }
            return ticket
        }()
        // Check digit is unused by assignPack once parse succeeds.
        let raw = "\(pack.gameNumber)-\(pack.packSerial)-\(paddedTicket)-0"
        try await assignPack(barcodeRaw: raw, toRowId: rowId)
    }

    /// Every bin on the current terminal — user can assign to any row.
    func allBinRows() -> [LotteryPackRackRow] {
        guard let template = templatesByTerminal[selectedTerminal] else { return [] }
        return template.rows.enumerated().map { index, row in
            rackRow(from: row, terminal: selectedTerminal, in: template, index: index)
        }
    }

    /// Bins sorted for assignment: empty → same game elsewhere → other occupied → current.
    func sortedBinRows(for barcode: OhioLotteryBarcode) -> [LotteryPackRackRow] {
        let rows = allBinRows()
        return rows.sorted { lhs, rhs in
            let left = assignSituation(row: lhs, barcode: barcode)
            let right = assignSituation(row: rhs, barcode: barcode)
            if left.sortRank != right.sortRank {
                return left.sortRank < right.sortRank
            }
            return lhs.binNumber.localizedStandardCompare(rhs.binNumber) == .orderedAscending
        }
    }

    /// Empty bins that could take this pack (suggested first).
    /// Empty bins preferred for a new pack (no pack serial and no Begin #).
    func suggestedEmptyBins(for barcode: OhioLotteryBarcode) -> [LotteryPackRackRow] {
        allBinRows().filter { assignSituation(row: $0, barcode: barcode) == .empty }
    }

    /// Other bins already holding this game # (different pack serial) — multiple packs OK.
    func binsWithSameGame(as barcode: OhioLotteryBarcode) -> [LotteryPackRackRow] {
        allBinRows().filter { row in
            guard row.hasActivePack else { return false }
            guard row.packSerial != barcode.packSerial else { return false }
            return OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, barcode.gameNumber)
        }
    }

    func assignSituation(row: LotteryPackRackRow, barcode: OhioLotteryBarcode) -> PackBinAssignSituation {
        if OhioLotteryBarcodeParser.packSerialsMatch(row.packSerial, barcode.packSerial) {
            return .currentLocation
        }
        if !row.looksOccupiedForAssign {
            return .empty
        }
        let existingSerial = (row.packSerial?.isEmpty == false) ? (row.packSerial ?? "") : "(no pack serial)"
        if row.gameNumber.isEmpty
            || OhioLotteryBarcodeParser.gameNumbersMatch(row.gameNumber, barcode.gameNumber) {
            return .replaceSameGame(existingSerial: existingSerial)
        }
        return .replaceDifferentGame(existingGame: row.gameNumber, existingSerial: existingSerial)
    }

    func requiresReplaceConfirmation(row: LotteryPackRackRow, barcode: OhioLotteryBarcode) -> Bool {
        switch assignSituation(row: row, barcode: barcode) {
        case .replaceSameGame, .replaceDifferentGame:
            return true
        case .currentLocation, .empty:
            return false
        }
    }

    func replaceConfirmationMessage(row: LotteryPackRackRow, barcode: OhioLotteryBarcode) -> String {
        guard let preview = finishedPackCloseoutPreview(row: row) else {
            switch assignSituation(row: row, barcode: barcode) {
            case .currentLocation, .empty:
                return ""
            case .replaceSameGame(let existingSerial):
                return "Bin \(row.binNumber) already has pack \(existingSerial) (Game \(row.gameNumber)). Assigning pack \(barcode.packSerial) will remove that pack from the rack."
            case .replaceDifferentGame(let existingGame, let existingSerial):
                return "Bin \(row.binNumber) already has Game \(existingGame), pack \(existingSerial). Assigning pack \(barcode.packSerial) (Game \(barcode.gameNumber)) will remove the current pack from this bin."
            }
        }

        let dollars = formatCurrency(preview.soldDollars)
        return "Bin \(row.binNumber) pack \(preview.packSerial) will be recorded as finished: Begin \(preview.beginningNumber) → 00 = \(preview.soldTickets) tickets (\(dollars)). That sale is added at the next shift close. Then pack \(barcode.packSerial) will be assigned with Begin \(barcode.ticketNumber.isEmpty ? "—" : barcode.ticketNumber)."
    }

    /// True when barcode is an open (non-sealed) pack — Begin will not be 00.
    func requiresOpenPackConfirmation(barcode: OhioLotteryBarcode) -> Bool {
        !barcode.isSealedPack
    }

    /// How many tickets look already sold from sealed start → scanned top ticket.
    func openPackAlreadySoldPreview(
        barcode: OhioLotteryBarcode,
        ticketsInBookOverride: String? = nil
    ) -> (ticketNumber: String, alreadySold: Int, ticketsInBook: String, dollarValue: String)? {
        guard !barcode.isSealedPack else { return nil }

        let tickets: String = {
            if let override = ticketsInBookOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                return override
            }
            if let game = gameDatabase.first(where: {
                OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, barcode.gameNumber)
            }) {
                return game.tickets
            }
            if let row = allBinRows().first(where: {
                OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, barcode.gameNumber)
                    && !$0.tickets.isEmpty
            }) {
                return row.tickets
            }
            return ""
        }()

        guard !tickets.isEmpty, Int(tickets) ?? 0 > 0 else {
            return (ticketNumber: barcode.ticketNumber, alreadySold: 0, ticketsInBook: "", dollarValue: "")
        }

        let reverseOrder = reverseOrder(for: selectedTerminal)
        let sealedBegin = LotteryCalculationService.sealedBeginTicket(
            ticketsInBook: tickets,
            reverseOrder: reverseOrder
        )
        let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: sealedBegin,
            ending: barcode.ticketNumber,
            tickets: tickets,
            reverseOrder: reverseOrder
        )
        let value = gameDatabase.first(where: {
            OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, barcode.gameNumber)
        })?.value ?? ""

        return (
            ticketNumber: barcode.ticketNumber,
            alreadySold: max(sold, 0),
            ticketsInBook: tickets,
            dollarValue: value
        )
    }

    func openPackConfirmationMessage(
        barcode: OhioLotteryBarcode,
        ticketsInBookOverride: String? = nil
    ) -> String {
        guard let preview = openPackAlreadySoldPreview(
            barcode: barcode,
            ticketsInBookOverride: ticketsInBookOverride
        ) else {
            return "This pack is sealed (ticket 00)."
        }

        let top = preview.ticketNumber.isEmpty ? "—" : preview.ticketNumber
        var message = "This pack is already open — top ticket is #\(top) (not a sealed 00).\n\n"
            if preview.alreadySold > 0 {
            message += "About \(preview.alreadySold) ticket\(preview.alreadySold == 1 ? "" : "s") look already sold from this book"
            if !preview.dollarValue.isEmpty {
                let soldDollars = Double(
                    LotteryCalculationService.calculateDollars(
                        sold: preview.alreadySold,
                        value: preview.dollarValue
                    )
                )
                message += " (\(formatCurrency(soldDollars)))"
            }
            message += ".\n\n"
        }
        message += "Begin # will be set to \(top). At shift close, sales are counted from that Begin → the End # you scan — so tickets sold while this pack is on the rack are included.\n\n"
        message += "Tickets sold before this assign are not added automatically. Only continue if that Begin # is correct."
        return message
    }

    /// Preview sold credit if the pack currently on this bin is finished and replaced.
    func finishedPackCloseoutPreview(row: LotteryPackRackRow) -> (
        packSerial: String,
        beginningNumber: String,
        soldTickets: Int,
        soldDollars: Double,
        books: Int
    )? {
        guard row.hasActivePack,
              let serial = row.packSerial, !serial.isEmpty,
              !row.beginningNumber.isEmpty,
              !row.tickets.isEmpty else { return nil }

        let reverseOrder = templatesByTerminal[selectedTerminal]?.reverseOrder ?? false
        let (sold, books) = LotteryCalculationService.calculateFinishedPackSold(
            beginning: row.beginningNumber,
            ticketsInBook: row.tickets,
            reverseOrder: reverseOrder,
            creditFullBookIfSealedBegin: false
        )
        let dollars = Double(LotteryCalculationService.calculateDollars(sold: sold, value: row.value))
        return (
            packSerial: serial,
            beginningNumber: row.beginningNumber,
            soldTickets: sold,
            soldDollars: dollars,
            books: books
        )
    }

    /// Rows on the current terminal that could receive this pack.
    @available(*, deprecated, message: "Use sortedBinRows(for:) — all bins are always available.")
    func candidateRows(for barcode: OhioLotteryBarcode) -> [LotteryPackRackRow] {
        sortedBinRows(for: barcode)
    }

    func assignPack(
        barcodeRaw: String,
        toRowId rowId: String,
        newGameValue: String? = nil,
        newGameTickets: String? = nil,
        confirmOpenPackForNewGame: Bool = false
    ) async throws {
        let parseResult = OhioLotteryBarcodeParser.parse(barcodeRaw)
        guard case .success(let barcode) = parseResult else {
            if case .failure(let error) = parseResult {
                throw LotteryPackAssignError.invalidBarcode(userMessage(for: error))
            }
            throw LotteryPackAssignError.invalidBarcode("Not a valid Ohio lottery barcode.")
        }

        let gameData: GameData
        if isKnownGame(barcode.gameNumber) {
            guard let resolved = try await resolveGameData(gameNumber: barcode.gameNumber) else {
                throw LotteryPackAssignError.gameNotInDatabase(barcode.gameNumber)
            }
            gameData = resolved
        } else {
            let value = LotteryGameTicketDefaults.normalizeValue(newGameValue ?? "")
            let tickets = LotteryGameTicketDefaults.normalizeTickets(newGameTickets ?? "") ?? ""
            guard !value.isEmpty, !tickets.isEmpty else {
                throw LotteryPackAssignError.newGameMissingDetails
            }
            if !barcode.isSealedPack && !confirmOpenPackForNewGame {
                throw LotteryPackAssignError.newGameMustBeSealedPack
            }
            gameData = try await addGameToDatabase(
                gameNumber: barcode.gameNumber,
                value: value,
                tickets: tickets
            )
        }

        await refreshSelectedTemplateFromServer()
        guard var template = templatesByTerminal[selectedTerminal] else {
            throw LotteryPackAssignError.noMatchingBin
        }

        guard let index = template.rows.firstIndex(where: { $0.id == rowId }) else {
            throw LotteryPackAssignError.noMatchingBin
        }

        let sourceIndex = template.rows.firstIndex(where: {
            OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, barcode.packSerial)
        })
        let isMove = sourceIndex != nil && sourceIndex != index
        let preservedEnding = sourceIndex.map { template.rows[$0].endingNumber } ?? ""

        let existingRow = template.rows[index]
        let isReplacingDifferentPack = rowHasActivePack(existingRow)
            && !OhioLotteryBarcodeParser.packSerialsMatch(existingRow.packSerial, barcode.packSerial)
            && sourceIndex != index

        let isSameGameReplace = isReplacingDifferentPack
            && OhioLotteryBarcodeParser.gameNumbersMatch(existingRow.gameNumber, gameData.gameNumber)

        var closeoutToSave: LotteryPackCloseout?
        // Same-game mid-shift swap: keep shift Begin and count Begin→End at close
        // (no sold-out closeout). Different game still credits the old pack finished.
        if isReplacingDifferentPack && !isSameGameReplace {
            let begin = existingRow.beginningNumber
            let tickets = existingRow.tickets
            let value = existingRow.value
            let oldSerial = existingRow.packSerial ?? ""
            if !begin.isEmpty, !tickets.isEmpty, !oldSerial.isEmpty {
                let (sold, books) = LotteryCalculationService.calculateFinishedPackSold(
                    beginning: begin,
                    ticketsInBook: tickets,
                    reverseOrder: template.reverseOrder,
                    creditFullBookIfSealedBegin: false
                )
                // Begin already sealed → swap with $0 sold-out credit (avoid West Jeff-style phantoms).
                // Partial Begin → end of book still credits normally.
                if sold > 0 {
                    let dollars = Double(LotteryCalculationService.calculateDollars(sold: sold, value: value))
                    let alreadyPending = pendingCloseouts.contains {
                        OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, oldSerial)
                    }
                    if alreadyPending {
                        throw LotteryPackAssignError.returnSaveFailed(
                            "A sold-out credit for pack \(oldSerial) is already pending. Close the current lottery shift before replacing this pack again."
                        )
                    }
                    closeoutToSave = LotteryPackCloseout(
                        locationId: location.id,
                        rowId: existingRow.id,
                        binNumber: displayBinNumber(for: existingRow, at: index),
                        gameNumber: existingRow.gameNumber,
                        packSerial: oldSerial,
                        beginningNumber: begin,
                        endingNumber: "00",
                        soldTickets: sold,
                        soldDollars: dollars,
                        books: books,
                        terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
                    )
                }
            }
        }

        let preservedBeginning = isSameGameReplace ? existingRow.beginningNumber : nil

        if !OhioLotteryBarcodeParser.packSerialsMatch(template.rows[index].packSerial, barcode.packSerial) {
            template.rows[index].endingNumber = ""
            template.rows[index].sold = ""
            template.rows[index].dollar = ""
            template.rows[index].books = ""
        }

        template.rows[index].gameNumber = OhioLotteryBarcodeParser.canonicalGameNumber(gameData.gameNumber)
        template.rows[index].value = gameData.value
        template.rows[index].tickets = gameData.tickets
        template.rows[index].packSerial = barcode.packSerial
        template.rows[index].packStatus = .active

        if let preservedBeginning, !preservedBeginning.isEmpty {
            template.rows[index].beginningNumber = preservedBeginning
        } else if !barcode.ticketNumber.isEmpty {
            template.rows[index].beginningNumber = barcode.ticketNumber
        }

        if isMove, !preservedEnding.isEmpty {
            template.rows[index].endingNumber = preservedEnding
        }

        if let sourceIndex, sourceIndex != index {
            clearBinRow(&template.rows[sourceIndex])
        }

        let stockToConsume = stockPacks.first {
            OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, barcode.packSerial)
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            if let closeoutToSave {
                try await firebaseService.createLotteryPackCloseout(
                    userId: managerUserId,
                    locationId: location.id,
                    closeout: closeoutToSave
                )
            }
            try await firebaseService.saveLotteryFormTemplate(
                userId: managerUserId,
                locationId: location.id,
                template: template
            )
            if let stock = stockToConsume {
                let binLabel = displayBinNumber(for: template.rows[index], at: index)
                try await firebaseService.markLotteryStockPackAssigned(
                    userId: managerUserId,
                    locationId: location.id,
                    packId: stock.id,
                    rowId: template.rows[index].id,
                    binNumber: binLabel
                )
                stockPacks.removeAll { $0.id == stock.id }
            }
            templatesByTerminal[selectedTerminal] = template
            await reloadPendingReturns()
            rebuildRackRows()
            let binLabel = displayBinNumber(for: template.rows[index], at: index)
            if let closeoutToSave {
                successMessage = "Finished pack \(closeoutToSave.packSerial) credited (\(closeoutToSave.soldTickets) tk). Pack \(barcode.packSerial) assigned to bin \(binLabel)."
            } else if isSameGameReplace {
                successMessage = "Same-game pack \(barcode.packSerial) on bin \(binLabel). Shift still counts from Begin \(preservedBeginning ?? "—")."
            } else if isMove {
                successMessage = "Pack \(barcode.packSerial) moved to bin \(binLabel)."
            } else {
                successMessage = "Pack \(barcode.packSerial) assigned to bin \(binLabel)."
            }
        } catch {
            throw LotteryPackAssignError.templateSaveFailed(error.localizedDescription)
        }
    }

    /// Match a scanned pack to its rack row (for returns).
    func matchedRow(for barcode: OhioLotteryBarcode) -> LotteryPackRackRow? {
        guard let template = templatesByTerminal[selectedTerminal] else { return nil }
        guard let row = template.rows.first(where: {
            OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, barcode.packSerial)
        }) else {
            return nil
        }
        return rackRow(from: row, terminal: selectedTerminal, in: template)
    }

    func returnPack(barcodeRaw: String) async throws {
        let parseResult = OhioLotteryBarcodeParser.parse(barcodeRaw)
        guard case .success(let barcode) = parseResult else {
            if case .failure(let error) = parseResult {
                throw LotteryPackAssignError.invalidBarcode(userMessage(for: error))
            }
            throw LotteryPackAssignError.invalidBarcode("Not a valid Ohio lottery barcode.")
        }

        await refreshSelectedTemplateFromServer()
        guard let template = templatesByTerminal[selectedTerminal],
              let index = template.rows.firstIndex(where: {
                  OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, barcode.packSerial)
              }) else {
            throw LotteryPackAssignError.packNotFound
        }

        try await submitReturn(
            rowId: template.rows[index].id,
            packSerial: barcode.packSerial,
            fromTicket: barcode.ticketNumber,
            isSealedPack: barcode.isSealedPack
        )
    }

    /// Return using the pack already on file for a bin (no barcode needed).
    func returnPackManually(rowId: String, fromTicket: String) async throws {
        let trimmed = fromTicket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LotteryPackAssignError.invalidBarcode("Enter the top ticket # showing when the pack was returned.")
        }

        await refreshSelectedTemplateFromServer()
        guard let template = templatesByTerminal[selectedTerminal],
              let index = template.rows.firstIndex(where: { $0.id == rowId }) else {
            throw LotteryPackAssignError.packNotFound
        }

        let row = template.rows[index]
        guard rowHasActivePack(row), let packSerial = row.packSerial, !packSerial.isEmpty else {
            throw LotteryPackAssignError.packNotActive
        }

        let ticket = normalizedReturnTicket(trimmed)
        let isSealed = ticket == "00"

        try await submitReturn(
            rowId: rowId,
            packSerial: packSerial,
            fromTicket: ticket,
            isSealedPack: isSealed
        )
    }

    private func submitReturn(
        rowId: String,
        packSerial: String,
        fromTicket: String,
        isSealedPack: Bool
    ) async throws {
        guard var template = templatesByTerminal[selectedTerminal] else {
            throw LotteryPackAssignError.packNotFound
        }

        guard let index = template.rows.firstIndex(where: { $0.id == rowId }) else {
            throw LotteryPackAssignError.packNotFound
        }

        let row = template.rows[index]
        guard rowHasActivePack(row) else {
            throw LotteryPackAssignError.packNotActive
        }

        let returnedTickets = LotteryCalculationService.calculateReturnedTickets(
            fromTicket: fromTicket,
            ticketsInBook: row.tickets,
            reverseOrder: template.reverseOrder,
            isSealedPack: isSealedPack
        )
        let returnedDollars = Double(
            LotteryCalculationService.calculateDollars(sold: returnedTickets, value: row.value)
        )

        // Nothing sold from Begin → return top → rack removal only, no close deduction.
        let (soldBeforeReturn, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber.isEmpty ? fromTicket : row.beginningNumber,
            ending: fromTicket,
            tickets: row.tickets,
            reverseOrder: template.reverseOrder
        )
        let skipDeduction = soldBeforeReturn == 0
            || LotteryShiftCloseScanMatcher.ticketNumbersEqual(row.beginningNumber, fromTicket)

        let bin = displayBinNumber(for: row, at: index)
        let lotteryReturn = LotteryReturn(
            locationId: location.id,
            rowId: row.id,
            binNumber: bin,
            gameNumber: row.gameNumber,
            packSerial: packSerial,
            returnedTickets: returnedTickets,
            returnedDollars: returnedDollars,
            ticketNumber: fromTicket,
            ticketValue: row.value,
            beginningNumber: row.beginningNumber,
            skipCloseDeduction: skipDeduction,
            terminalNumber: selectedTerminal > 1 ? selectedTerminal : nil
        )

        clearBinRow(&template.rows[index])

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            try await firebaseService.createLotteryReturn(
                userId: managerUserId,
                locationId: location.id,
                lotteryReturn: lotteryReturn
            )
            try await firebaseService.saveLotteryFormTemplate(
                userId: managerUserId,
                locationId: location.id,
                template: template
            )
            templatesByTerminal[selectedTerminal] = template
            await reloadPendingReturns()
            rebuildRackRows()
            if skipDeduction {
                successMessage = "Pack removed from rack. Nothing sold from this pack — $0 impact at shift close (\(returnedTickets) tk still on book for records)."
            } else {
                successMessage = "Return recorded: \(returnedTickets) tickets (\(formatCurrency(returnedDollars))). Applies at next shift close."
            }
        } catch {
            throw LotteryPackAssignError.returnSaveFailed(error.localizedDescription)
        }
    }

    private func rowHasActivePack(_ row: LotteryFormTemplateRow) -> Bool {
        guard let serial = row.packSerial, !serial.isEmpty else { return false }
        switch row.packStatus {
        case .active: return true
        case .returned, .empty: return false
        case nil: return true
        }
    }

    private func normalizedReturnTicket(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = OhioLotteryBarcodeParser.normalizeTicketPosition(trimmed)
        if !normalized.isEmpty { return normalized }
        return trimmed
    }

    private func clearBinRow(_ row: inout LotteryFormTemplateRow) {
        row.packSerial = nil
        row.packStatus = nil
        row.gameNumber = ""
        row.value = ""
        row.tickets = ""
        row.beginningNumber = ""
        row.endingNumber = ""
        row.sold = ""
        row.dollar = ""
        row.books = ""
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func rebuildRackRows() {
        guard let template = templatesByTerminal[selectedTerminal] else {
            rackRows = []
            return
        }
        rackRows = template.rows.enumerated().map { index, row in
            rackRow(from: row, terminal: selectedTerminal, index: index)
        }
    }

    private func displayBinNumber(for row: LotteryFormTemplateRow, at index: Int) -> String {
        row.binNumber.isEmpty ? String(index + 1) : row.binNumber
    }

    private func rackRow(
        from row: LotteryFormTemplateRow,
        terminal: Int,
        in template: LotteryFormTemplate,
        index: Int? = nil
    ) -> LotteryPackRackRow {
        let resolvedIndex = index ?? template.rows.firstIndex(where: { $0.id == row.id }) ?? 0
        return LotteryPackRackRow(
            id: row.id,
            binNumber: displayBinNumber(for: row, at: resolvedIndex),
            gameNumber: row.gameNumber,
            value: row.value,
            tickets: row.tickets,
            packSerial: row.packSerial,
            packStatus: row.packStatus,
            beginningNumber: row.beginningNumber,
            terminalNumber: terminal
        )
    }

    private func rackRow(from row: LotteryFormTemplateRow, terminal: Int, index: Int) -> LotteryPackRackRow {
        guard let template = templatesByTerminal[terminal] else {
            return LotteryPackRackRow(
                id: row.id,
                binNumber: displayBinNumber(for: row, at: index),
                gameNumber: row.gameNumber,
                value: row.value,
                tickets: row.tickets,
                packSerial: row.packSerial,
                packStatus: row.packStatus,
                beginningNumber: row.beginningNumber,
                terminalNumber: terminal
            )
        }
        return rackRow(from: row, terminal: terminal, in: template, index: index)
    }

    private func userMessage(for error: OhioLotteryBarcodeParser.ParseError) -> String {
        switch error {
        case .empty: return "Enter or scan a barcode."
        case .invalidFormat: return "Barcode format isn't valid. Expected ####-#######-###-#."
        case .notLotteryBarcode: return "That doesn't look like a lottery pack barcode."
        }
    }

    private func resolveGameData(gameNumber: String) async throws -> GameData? {
        let canonical = OhioLotteryBarcodeParser.canonicalGameNumber(gameNumber)
        if let match = gameDatabase.first(where: {
            OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, canonical)
        }) {
            return match
        }
        for candidate in OhioLotteryBarcodeParser.gameLookupCandidates(gameNumber) {
            if let game = try await firebaseService.fetchGameData(gameNumber: candidate) {
                return game
            }
        }
        return nil
    }

    private func addGameToDatabase(gameNumber: String, value: String, tickets: String) async throws -> GameData {
        let canonical = OhioLotteryBarcodeParser.canonicalGameNumber(gameNumber)
        if let existing = gameDatabase.first(where: {
            OhioLotteryBarcodeParser.gameNumbersMatch($0.gameNumber, canonical)
        }) {
            return existing
        }

        let game = GameData(gameNumber: canonical, value: value, tickets: tickets)
        do {
            try await firebaseService.saveGameData(game)
        } catch {
            throw LotteryPackAssignError.gameSaveFailed(error.localizedDescription)
        }
        gameDatabase.append(game)
        gameDatabase.sort { $0.gameNumber.localizedStandardCompare($1.gameNumber) == .orderedAscending }
        return game
    }
}

extension PackBinAssignSituation {
    /// Lower = listed first in the bin picker.
    var sortRank: Int {
        switch self {
        case .empty: return 0
        case .replaceSameGame: return 1
        case .replaceDifferentGame: return 2
        case .currentLocation: return 3
        }
    }
}
