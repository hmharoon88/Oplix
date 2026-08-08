//
//  GameDatabaseView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct GameDatabaseView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = GameDatabaseViewModel()
    @State private var gameToDelete: GameData?
    @State private var showingDeleteConfirmation = false
    @State private var editingRows: [String: EditableGameData] = [:] // Track editing state for each row
    @State private var saveTasks: [String: Task<Void, Never>] = [:] // Track save tasks for debouncing
    @State private var isImporting = false
    @State private var showingImportSuccess = false
    @State private var importedCount = 0
    @State private var focusedField: FocusedField? // Track which field is focused
    @State private var newRowIds: Set<String> = [] // Track which rows are new (not yet saved)
    @State private var isSaving = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingConflictAlert = false
    @State private var conflictData: (new: GameData, existing: GameData)?
    @State private var pendingSaves: [GameData] = [] // Queue for saves after conflict resolution
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.leading)
                    
                    Spacer()
                    
                    Text("Game Database")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            Task {
                                await bulkImportGames()
                            }
                        }) {
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(isImporting)
                        
                        // Save All button (only show if there are new rows)
                        if !newRowIds.isEmpty {
                            Button(action: {
                                Task {
                                    await saveAllNewRows()
                                }
                            }) {
                                if isSaving {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Text("Save All")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .disabled(isSaving)
                        }
                        
                        Button(action: {
                            // Add new empty row directly
                            let newGame = GameData(gameNumber: "", value: "", tickets: "")
                            viewModel.gameDataList.append(newGame)
                            editingRows[newGame.id] = EditableGameData(gameNumber: "", value: "", tickets: "")
                            newRowIds.insert(newGame.id) // Mark as new row
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing)
                }
                .frame(height: 60)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.3, blue: 0.6),
                            Color(red: 0.15, green: 0.4, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Table
                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading game database...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.gameDataList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No Game Data")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap '+' to add a new game")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Fixed Header Row (always visible)
                        HStack(spacing: 0) {
                            headerCell("#")
                            headerCell("Game Number")
                            headerCell("Value")
                            headerCell("Tickets")
                            headerCell("") // Delete button column
                        }
                        .background(Theme.cloudBlue.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.5)),
                            alignment: .bottom
                        )
                        
                        // Scrollable Data Rows
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.gameDataList.enumerated()), id: \.element.id) { index, gameData in
                                    gameDataRow(index: index, gameData: gameData)
                                }
                            }
                            .overlay(
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .leading
                            )
                            .overlay(
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .trailing
                            )
                        }
                        .background(Theme.cloudWhite)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadGameData()
            }
        }
        .onChange(of: viewModel.gameDataList) {
            // Initialize editing state for new rows
            for gameData in viewModel.gameDataList {
                if editingRows[gameData.id] == nil {
                    editingRows[gameData.id] = EditableGameData(
                        gameNumber: gameData.gameNumber,
                        value: gameData.value,
                        tickets: gameData.tickets
                    )
                }
            }
        }
        .alert("Delete Game", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                gameToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let gameData = gameToDelete {
                    Task {
                        await viewModel.deleteGameData(gameData)
                        gameToDelete = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this game data?")
        }
        .alert("Bulk Import Complete", isPresented: $showingImportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Successfully imported \(importedCount) games into the database.")
        }
        .alert("Save Result", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .alert("Duplicate Game Number", isPresented: $showingConflictAlert) {
            Button("Keep Existing") {
                Task {
                    await handleConflictResolution(keepNew: false)
                }
            }
            Button("Replace with New") {
                Task {
                    await handleConflictResolution(keepNew: true)
                }
            }
            Button("Cancel", role: .cancel) {
                conflictData = nil
                pendingSaves = []
                isSaving = false
            }
        } message: {
            if let conflict = conflictData {
                Text("Game number '\(conflict.new.gameNumber)' already exists.\n\nExisting: Value: $\(conflict.existing.value), Tickets: \(conflict.existing.tickets)\nNew: Value: $\(conflict.new.value), Tickets: \(conflict.new.tickets)\n\nWhich one would you like to keep?")
            } else {
                Text("A conflict was detected.")
            }
        }
    }
    
    private func bulkImportGames() async {
        isImporting = true
        var imported = 0
        
        // Define all games to import
        let gamesToImport: [(gameNumber: String, value: String, tickets: String)] = [
            // $50 games (3): 30 tickets each
            ("0827", "50", "30"),
            ("0762", "50", "30"),
            ("1008", "50", "30"),
            
            // $30 games (7): 25 tickets each
            ("0863", "30", "25"),
            ("0785", "30", "25"),
            ("0433", "30", "25"),
            ("0882", "30", "25"),
            ("0853", "30", "25"),
            ("696", "30", "25"),
            ("1024", "30", "25"),
            
            // $20 games (12): 25 tickets each
            ("0858", "20", "25"),
            ("0870", "20", "25"),
            ("1032", "20", "25"),
            ("0892", "20", "25"),
            ("0888", "20", "25"),
            ("1019", "20", "25"),
            ("0671", "20", "25"),
            ("1028", "20", "25"),
            ("0833", "20", "25"),
            ("0880", "20", "25"),
            ("1013", "20", "25"),
            ("1043", "20", "25"),
            
            // $10 games (19): 50 tickets each
            ("0872", "10", "50"),
            ("1031", "10", "50"),
            ("0875", "10", "50"),
            ("1026", "10", "50"),
            ("0852", "10", "50"),
            ("0847", "10", "50"),
            ("1007", "10", "50"),
            ("1023", "10", "50"),
            ("1017", "10", "50"),
            ("0869", "10", "50"),
            ("0826", "10", "50"),
            ("0862", "10", "50"),
            ("0879", "10", "50"),
            ("0842", "10", "50"),
            ("1012", "10", "50"),
            ("0857", "10", "50"),
            ("1036", "10", "50"),
            ("1042", "10", "50"),
            ("1047", "10", "50"),
            ("1234", "10", "50"),
            
            // $5 games (17): 50 tickets each
            ("0856", "5", "50"),
            ("0893", "5", "50"),
            ("1050", "5", "50"),
            ("1022", "5", "50"),
            ("0845", "5", "50"),
            ("1038", "5", "50"),
            ("0891", "5", "50"),
            ("0861", "5", "50"),
            ("1006", "5", "50"),
            ("1030", "5", "50"),
            ("0886", "5", "50"),
            ("1011", "5", "50"),
            ("1035", "5", "50"),
            ("1016", "5", "50"),
            ("1037", "5", "50"),
            ("1041", "5", "50"),
            ("1046", "5", "50"),
            
            // $2 games (17): 100 tickets each
            ("0855", "2", "100"),
            ("1005", "2", "100"),
            ("0883", "2", "100"),
            ("0890", "2", "100"),
            ("0849", "2", "100"),
            ("0871", "2", "100"),
            ("1027", "2", "100"),
            ("0860", "2", "100"),
            ("0885", "2", "100"),
            ("0867", "2", "100"),
            ("0877", "2", "100"),
            ("1029", "2", "100"),
            ("1010", "2", "100"),
            ("1034", "2", "100"),
            ("1015", "2", "100"),
            ("1021", "2", "100"),
            ("1040", "2", "100"),
            
            // $1 games (11): 200 tickets each
            ("0859", "1", "200"),
            ("0848", "1", "200"),
            ("0876", "1", "200"),
            ("1020", "1", "200"),
            ("0829", "1", "200"),
            ("1004", "1", "200"),
            ("1009", "1", "200"),
            ("0884", "1", "200"),
            ("0873", "1", "200"),
            ("1052", "1", "200"),
            ("1033", "1", "200"),
            
            // Special case: Game "1018" - $10 value, 30 tickets
            ("1018", "10", "30")
        ]
        
        // Check existing games to avoid duplicates
        let existingGameNumbers = Set(viewModel.gameDataList.map { $0.gameNumber })
        
        // Import games
        for game in gamesToImport {
            // Skip if game already exists
            if existingGameNumbers.contains(game.gameNumber) {
                continue
            }
            
            let gameData = GameData(
                gameNumber: game.gameNumber,
                value: game.value,
                tickets: game.tickets
            )
            
            do {
                try await viewModel.saveGameData(gameData)
                imported += 1
            } catch {
                print("Failed to import game \(game.gameNumber): \(error.localizedDescription)")
            }
        }
        
        // Reload the list
        await viewModel.loadGameData()
        
        importedCount = imported
        isImporting = false
        showingImportSuccess = true
    }
    
    private var columnWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16
        let availableWidth = screenWidth - padding * 2
        return availableWidth / 5 // 4 data columns + 1 delete button column
    }
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .frame(width: columnWidth, height: 44)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
    }
    
    // Helper function to create a row for a game data item
    private func gameDataRow(index: Int, gameData: GameData) -> some View {
        let isLastRow = index == viewModel.gameDataList.count - 1
        _ = true // For tickets field
        let isNewRow = newRowIds.contains(gameData.id)
        
        return HStack(spacing: 0) {
            // Row number (read-only)
            readOnlyCell(String(index + 1))
            
            // Editable cells
            GameNumberPadTextField(
                text: bindingForGameNumber(gameData: gameData),
                fieldId: "\(gameData.id).gameNumber",
                focusedField: $focusedField,
                isLastField: false,
                isLastRow: isLastRow,
                onNext: {
                    moveToNextField(currentField: "\(gameData.id).gameNumber", currentRowIndex: index)
                },
                onDone: {
                    focusedField = nil
                }
            )
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            
            GameNumberPadTextField(
                text: bindingForValue(gameData: gameData),
                fieldId: "\(gameData.id).value",
                focusedField: $focusedField,
                isLastField: false,
                isLastRow: isLastRow,
                onNext: {
                    moveToNextField(currentField: "\(gameData.id).value", currentRowIndex: index)
                },
                onDone: {
                    focusedField = nil
                }
            )
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            
            GameNumberPadTextField(
                text: bindingForTickets(gameData: gameData),
                fieldId: "\(gameData.id).tickets",
                focusedField: $focusedField,
                isLastField: true,
                isLastRow: isLastRow,
                onNext: {
                    moveToNextField(currentField: "\(gameData.id).tickets", currentRowIndex: index)
                },
                onDone: {
                    focusedField = nil
                }
            )
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            
            // Delete button
            Button(action: {
                gameToDelete = gameData
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
            }
            .frame(width: columnWidth, height: 44)
        }
        .background(isNewRow ? Color.yellow.opacity(0.1) : Theme.cloudWhite) // Highlight new rows
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .bottom
        )
    }
    
    private func moveToNextField(currentField: String, currentRowIndex: Int) {
        let parts = currentField.split(separator: ".")
        guard parts.count == 2, let gameDataId = parts.first else { return }
        let fieldType = String(parts[1])
        
        switch fieldType {
        case "gameNumber":
            // Move to value field in same row (horizontal)
            focusedField = .field("\(gameDataId).value")
        case "value":
            // Move to tickets field in same row (horizontal)
            focusedField = .field("\(gameDataId).tickets")
        case "tickets":
            // Last field in row - dismiss keyboard (don't move vertically)
            focusedField = nil
        default:
            focusedField = nil
        }
    }
    
    // Helper functions to create bindings for each field
    private func bindingForGameNumber(gameData: GameData) -> Binding<String> {
        Binding(
            get: { editingRows[gameData.id]?.gameNumber ?? gameData.gameNumber },
            set: { newValue in
                initializeEditingRowIfNeeded(gameData: gameData)
                editingRows[gameData.id]?.gameNumber = newValue
                saveGameDataIfNeeded(gameDataId: gameData.id)
            }
        )
    }
    
    private func bindingForValue(gameData: GameData) -> Binding<String> {
        Binding(
            get: { 
                // Return value without $ prefix - the text field handles display formatting
                let value = editingRows[gameData.id]?.value ?? gameData.value
                return value.replacingOccurrences(of: "$", with: "")
            },
            set: { newValue in
                initializeEditingRowIfNeeded(gameData: gameData)
                // Remove $ sign before storing
                let cleanValue = newValue.replacingOccurrences(of: "$", with: "")
                editingRows[gameData.id]?.value = cleanValue
                saveGameDataIfNeeded(gameDataId: gameData.id)
            }
        )
    }
    
    private func bindingForTickets(gameData: GameData) -> Binding<String> {
        Binding(
            get: { editingRows[gameData.id]?.tickets ?? gameData.tickets },
            set: { newValue in
                initializeEditingRowIfNeeded(gameData: gameData)
                editingRows[gameData.id]?.tickets = newValue
                saveGameDataIfNeeded(gameDataId: gameData.id)
            }
        )
    }
    
    // Helper function to initialize editing row if needed
    private func initializeEditingRowIfNeeded(gameData: GameData) {
        if editingRows[gameData.id] == nil {
            editingRows[gameData.id] = EditableGameData(
                gameNumber: gameData.gameNumber,
                value: gameData.value,
                tickets: gameData.tickets
            )
        }
    }
    
    private func readOnlyCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
    }
    
    
    // Save game data with debouncing (only for existing rows)
    private func saveGameDataIfNeeded(gameDataId: String) {
        // Don't auto-save new rows - they should be saved via "Save All" button
        guard !newRowIds.contains(gameDataId),
              let gameData = viewModel.gameDataList.first(where: { $0.id == gameDataId }),
              let editedData = editingRows[gameDataId] else { return }
        
        // Cancel previous save task for this row
        saveTasks[gameDataId]?.cancel()
        
        // Create new debounced save task
        saveTasks[gameDataId] = Task {
            // Wait 1 second after user stops typing
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Check if data has changed
            if editedData.gameNumber != gameData.gameNumber ||
               editedData.value != gameData.value ||
               editedData.tickets != gameData.tickets {
                
                // Only save if all fields are filled
                if !editedData.gameNumber.isEmpty && !editedData.value.isEmpty && !editedData.tickets.isEmpty {
                    let updatedGameData = GameData(
                        id: gameData.id,
                        gameNumber: editedData.gameNumber,
                        value: editedData.value,
                        tickets: editedData.tickets,
                        createdAt: gameData.createdAt,
                        lastUpdated: Date()
                    )
                    
                    do {
                        try await viewModel.saveGameData(updatedGameData)
                    } catch {
                        print("Failed to save game data: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Save all new rows at once
    private func saveAllNewRows() async {
        isSaving = true
        var savedCount = 0
        var errorCount = 0
        
        // Get all new rows that have all fields filled
        let rowsToSave = viewModel.gameDataList.filter { gameData in
            guard newRowIds.contains(gameData.id),
                  let editedData = editingRows[gameData.id] else { return false }
            return !editedData.gameNumber.isEmpty && 
                   !editedData.value.isEmpty && 
                   !editedData.tickets.isEmpty
        }
        
        // Check for duplicates and conflicts
        var processedRows: [GameData] = []
        let rowsToProcess = rowsToSave
        
        for gameData in rowsToProcess {
            guard let editedData = editingRows[gameData.id] else { continue }
            
            let gameDataToSave = GameData(
                id: gameData.id,
                gameNumber: editedData.gameNumber,
                value: editedData.value,
                tickets: editedData.tickets,
                createdAt: gameData.createdAt,
                lastUpdated: Date()
            )
            
            // Check if this game number already exists in the database
            if let existingGame = await viewModel.fetchGameData(gameNumber: editedData.gameNumber) {
                // Check if it's the same game data (same ID) - skip if it's the same
                if existingGame.id == gameData.id {
                    // Same game, just update it
                    processedRows.append(gameDataToSave)
                    continue
                }
                
                // Different game with same number - check if values are different
                if existingGame.value != editedData.value || existingGame.tickets != editedData.tickets {
                    // Conflict detected - show alert and pause processing
                    conflictData = (new: gameDataToSave, existing: existingGame)
                    showingConflictAlert = true
                    isSaving = false
                    // Store remaining rows to process after conflict resolution
                    pendingSaves = Array(rowsToProcess.dropFirst(rowsToProcess.firstIndex(where: { $0.id == gameData.id })! + 1))
                    return
                } else {
                    // Same values - skip this new row (keep existing)
                    // Remove from new rows
                    if let index = viewModel.gameDataList.firstIndex(where: { $0.id == gameData.id }) {
                        viewModel.gameDataList.remove(at: index)
                        editingRows.removeValue(forKey: gameData.id)
                        newRowIds.remove(gameData.id)
                    }
                    continue
                }
            }
            
            // Check for duplicates within the rows being saved
            if processedRows.contains(where: { $0.gameNumber == editedData.gameNumber }) {
                // Duplicate in new rows - skip this one
                if let index = viewModel.gameDataList.firstIndex(where: { $0.id == gameData.id }) {
                    viewModel.gameDataList.remove(at: index)
                    editingRows.removeValue(forKey: gameData.id)
                    newRowIds.remove(gameData.id)
                }
                continue
            }
            
            // No conflict - add to processed rows
            processedRows.append(gameDataToSave)
        }
        
        // Save all processed rows
        await saveRows(processedRows, savedCount: &savedCount, errorCount: &errorCount)
        
        // Remove incomplete rows
        removeIncompleteRows()
        
        isSaving = false
        
        // Show result
        if errorCount > 0 {
            saveErrorMessage = "Saved \(savedCount) rows. \(errorCount) rows had errors."
            showingSaveError = true
        } else if savedCount > 0 {
            saveErrorMessage = "Successfully saved \(savedCount) row(s)."
            showingSaveError = true
        }
        
        // Reload data to refresh the list
        await viewModel.loadGameData()
    }
    
    // Helper function to save rows
    private func saveRows(_ rows: [GameData], savedCount: inout Int, errorCount: inout Int) async {
        for gameData in rows {
            do {
                try await viewModel.saveGameData(gameData)
                savedCount += 1
                // Remove from new rows set after successful save
                newRowIds.remove(gameData.id)
            } catch {
                errorCount += 1
                print("Failed to save game \(gameData.id): \(error.localizedDescription)")
            }
        }
    }
    
    // Helper function to remove incomplete rows
    private func removeIncompleteRows() {
        let incompleteRows = viewModel.gameDataList.filter { gameData in
            guard newRowIds.contains(gameData.id),
                  let editedData = editingRows[gameData.id] else { return false }
            return editedData.gameNumber.isEmpty || 
                   editedData.value.isEmpty || 
                   editedData.tickets.isEmpty
        }
        
        for incompleteRow in incompleteRows {
            if let index = viewModel.gameDataList.firstIndex(where: { $0.id == incompleteRow.id }) {
                viewModel.gameDataList.remove(at: index)
                editingRows.removeValue(forKey: incompleteRow.id)
                newRowIds.remove(incompleteRow.id)
            }
        }
    }
    
    // Handle conflict resolution
    private func handleConflictResolution(keepNew: Bool) async {
        guard let conflict = conflictData else { return }
        
        var savedCount = 0
        var errorCount = 0
        
        if keepNew {
            // Delete existing and save new
            do {
                await viewModel.deleteGameData(conflict.existing)
                try await viewModel.saveGameData(conflict.new)
                savedCount += 1
                newRowIds.remove(conflict.new.id)
            } catch {
                errorCount += 1
                print("Failed to replace game: \(error.localizedDescription)")
            }
        } else {
            // Keep existing, remove new row
            if let index = viewModel.gameDataList.firstIndex(where: { $0.id == conflict.new.id }) {
                viewModel.gameDataList.remove(at: index)
                editingRows.removeValue(forKey: conflict.new.id)
                newRowIds.remove(conflict.new.id)
            }
        }
        
        conflictData = nil
        
        // Continue processing pending saves
        if !pendingSaves.isEmpty {
            isSaving = true
            var processedRows: [GameData] = []
            
            for gameData in pendingSaves {
                guard let editedData = editingRows[gameData.id] else { continue }
                
                let gameDataToSave = GameData(
                    id: gameData.id,
                    gameNumber: editedData.gameNumber,
                    value: editedData.value,
                    tickets: editedData.tickets,
                    createdAt: gameData.createdAt,
                    lastUpdated: Date()
                )
                
                // Check for duplicates
                if let existingGame = await viewModel.fetchGameData(gameNumber: editedData.gameNumber) {
                    if existingGame.id != gameData.id {
                        if existingGame.value != editedData.value || existingGame.tickets != editedData.tickets {
                            // Another conflict
                            conflictData = (new: gameDataToSave, existing: existingGame)
                            showingConflictAlert = true
                            pendingSaves = Array(pendingSaves.dropFirst(pendingSaves.firstIndex(where: { $0.id == gameData.id })! + 1))
                            isSaving = false
                            return
                        } else {
                            // Same values - skip
                            if let index = viewModel.gameDataList.firstIndex(where: { $0.id == gameData.id }) {
                                viewModel.gameDataList.remove(at: index)
                                editingRows.removeValue(forKey: gameData.id)
                                newRowIds.remove(gameData.id)
                            }
                            continue
                        }
                    }
                }
                
                if !processedRows.contains(where: { $0.gameNumber == editedData.gameNumber }) {
                    processedRows.append(gameDataToSave)
                }
            }
            
            await saveRows(processedRows, savedCount: &savedCount, errorCount: &errorCount)
            removeIncompleteRows()
            isSaving = false
        }
        
        // Show result
        if errorCount > 0 {
            saveErrorMessage = "Saved \(savedCount) rows. \(errorCount) rows had errors."
            showingSaveError = true
        } else if savedCount > 0 || !keepNew {
            saveErrorMessage = "Successfully saved \(savedCount) row(s)."
            showingSaveError = true
        }
        
        // Reload data
        await viewModel.loadGameData()
    }
}

// Helper struct to track editing state
struct EditableGameData {
    var gameNumber: String
    var value: String
    var tickets: String
}

// ViewModel for Game Database
@MainActor
class GameDatabaseViewModel: ObservableObject {
    @Published var gameDataList: [GameData] = []
    @Published var isLoading = false
    
    private let firebaseService = FirebaseService.shared
    
    func loadGameData() async {
        isLoading = true
        do {
            gameDataList = try await firebaseService.fetchAllGameData()
        } catch {
            print("Failed to load game data: \(error.localizedDescription)")
            gameDataList = []
        }
        isLoading = false
    }
    
    func saveGameData(_ gameData: GameData) async throws {
        try await firebaseService.saveGameData(gameData)
        await loadGameData() // Reload to refresh list
    }
    
    func deleteGameData(_ gameData: GameData) async {
        do {
            try await firebaseService.deleteGameData(gameDataId: gameData.id)
            await loadGameData() // Reload to refresh list
        } catch {
            print("Failed to delete game data: \(error.localizedDescription)")
        }
    }
    
    func fetchGameData(gameNumber: String) async -> GameData? {
        do {
            return try await firebaseService.fetchGameData(gameNumber: gameNumber)
        } catch {
            print("Failed to fetch game data: \(error.localizedDescription)")
            return nil
        }
    }
}

// Focus field identifier
enum FocusedField: Hashable {
    case field(String)
}

// MARK: - Number Pad TextField with Toolbar for Game Database
struct GameNumberPadTextField: UIViewRepresentable {
    @Binding var text: String
    let fieldId: String
    @Binding var focusedField: FocusedField?
    let isLastField: Bool
    let isLastRow: Bool
    let onNext: () -> Void
    let onDone: () -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 11)
        textField.delegate = context.coordinator
        
        // No toolbar - keyboard appears without Done/Next buttons
        textField.inputAccessoryView = nil
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // CRITICAL: Never interfere with text field when user is actively typing
        // This prevents cursor jumping and focus loss
        if uiView.isFirstResponder {
            // User is actively typing - completely ignore updates from SwiftUI
            // The text field manages its own state during editing
            return
        }
        
        // Also check if this field is marked as focused (even if not currently first responder)
        // This prevents updates during brief focus transitions
        if case .field(let id) = focusedField, id == fieldId {
            // This field is supposed to be focused - don't update it
            return
        }
        
        // Only update when field is NOT focused (user is not typing)
        // Handle value display for "value" field (add $ prefix for display)
        if fieldId.contains(".value") {
            let currentValue = text
            let cleanValue = currentValue.replacingOccurrences(of: "$", with: "")
            if !cleanValue.isEmpty {
                let displayValue = "$\(cleanValue)"
                if uiView.text != displayValue {
                    uiView.text = displayValue
                }
            } else {
                if uiView.text != "" {
                    uiView.text = ""
                }
            }
        } else {
            if uiView.text != text {
                uiView.text = text
            }
        }
        
        // Don't manage focus programmatically - let user control it naturally
        // Removing focus management to prevent unwanted focus changes
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: GameNumberPadTextField
        
        init(_ parent: GameNumberPadTextField) {
            self.parent = parent
        }
        
        @objc func nextTapped() {
            parent.onNext()
        }
        
        @objc func doneTapped() {
            parent.onDone()
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // For value field, handle $ prefix manually so the binding stays numeric
            if parent.fieldId.contains(".value") {
                // Apply the edit against the displayed text (which may include "$"),
                // then strip "$" for storage. Using the delegate's `range` preserves
                // cursor-position-aware insertion/deletion (i.e. multi-digit entry).
                let currentDisplay = (textField.text ?? "") as NSString
                let safeRange = NSRange(
                    location: min(range.location, currentDisplay.length),
                    length: min(range.length, max(0, currentDisplay.length - range.location))
                )
                let newDisplay = currentDisplay.replacingCharacters(in: safeRange, with: string)
                let cleanText = newDisplay.replacingOccurrences(of: "$", with: "")

                // Compute new cursor position in the displayed string ("$" + digits)
                let insertedCount = (string as NSString).length
                var newCursorInClean = max(0, safeRange.location - (currentDisplay.hasPrefix("$") ? 1 : 0)) + insertedCount
                newCursorInClean = min(newCursorInClean, (cleanText as NSString).length)
                let newCursorInDisplay = newCursorInClean + (cleanText.isEmpty ? 0 : 1) // account for "$"

                parent.text = cleanText
                textField.text = cleanText.isEmpty ? "" : "$\(cleanText)"

                if let position = textField.position(from: textField.beginningOfDocument, offset: newCursorInDisplay) {
                    textField.selectedTextRange = textField.textRange(from: position, to: position)
                }

                return false // We handle the text update ourselves
            } else {
                // For other fields, allow default behavior and update binding
                let currentText = textField.text ?? ""
                let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
                parent.text = newText
                return true // Allow default behavior
            }
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Immediately set focused field when editing begins
            // This prevents updateUIView from interfering with this field
            parent.focusedField = .field(parent.fieldId)
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            // Clear focused field when editing ends to allow updates
            if case .field(let id) = parent.focusedField, id == parent.fieldId {
                parent.focusedField = nil
            }
        }
    }
}

