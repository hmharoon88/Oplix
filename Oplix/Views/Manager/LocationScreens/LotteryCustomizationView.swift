//
//  LotteryCustomizationView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

/// Per-terminal draft held in memory while the manager is editing.
/// Each terminal has its own row list, register float, and reverse-
/// order toggle — they're independent chains, so they have to be
/// independent drafts.
private struct TerminalDraft {
    var rows: [LotteryFormTemplateRow] = []
    var lotteryRegisterAmount: String = ""
    var reverseOrder: Bool = false
    /// True once the manager has touched any field on this terminal
    /// during the current customization session. We only write dirty
    /// drafts back to Firestore on Save so we don't churn the
    /// `lastUpdated` timestamp on terminals nobody edited.
    var isDirty: Bool = false
}

struct LotteryCustomizationView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var formRows: [LotteryFormTemplateRow] = []
    @State private var rowToDelete: LotteryFormTemplateRow?
    @State private var showingDeleteConfirmation = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var lotteryRegisterAmount: String = ""
    @State private var reverseOrder: Bool = false
    @State private var validationMessage: String?
    @State private var showingValidationMessage = false

    // MARK: - Multi-terminal state
    //
    // `terminalCount` and `archivedTerminals` are the staged values —
    // the manager's edits don't hit `Location` until they tap Save.
    // `terminalDrafts` is the in-memory editing state for each
    // terminal; we lazy-load each terminal's template the first time
    // it's selected so that bumping the count from 2 to 5 doesn't fire
    // 3 unnecessary fetches up-front.
    @State private var terminalCount: Int = 1
    @State private var selectedTerminal: Int = 1
    @State private var archivedTerminals: [Int] = []
    @State private var terminalDrafts: [Int: TerminalDraft] = [:]
    @State private var didReduceTerminals: Bool = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Done button
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.leading)
                    
                    Spacer()
                    
                    Text("Lottery Form Customization")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Save") {
                        Task {
                            await saveTemplate()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.trailing)
                    .disabled(isSaving)
                    .overlay(
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                    )
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
                
                // Terminal controls — only meaningful for multi-terminal
                // locations. Single-terminal locations still see the
                // stepper (so they can opt in by raising it to 2) but
                // no tab strip until count > 1.
                terminalControlsSection

                // Lottery Register Amount and Reverse Order Toggle
                // (per-terminal: both fields apply to whichever terminal
                // is currently selected above).
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Text(terminalCount > 1
                             ? "Register Amount (Terminal \(selectedTerminal)):"
                             : "Lottery Register Amount:")
                            .font(.headline)
                            .foregroundColor(.black)

                        TextField("Enter amount", text: $lotteryRegisterAmount)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 200)
                            .onChange(of: lotteryRegisterAmount) {
                                markCurrentTerminalDirty()
                            }
                    }
                    .padding(.horizontal)

                    Toggle("Reverse Order", isOn: $reverseOrder)
                        .padding(.horizontal)
                        .onChange(of: reverseOrder) {
                            // Recalculate all rows when reverse order changes
                            for index in formRows.indices {
                                calculateRowValues(for: index)
                            }
                            markCurrentTerminalDirty()
                        }
                }
                .padding(.vertical, 12)
                .background(Theme.cloudWhite)
                
                // Add/Delete Buttons
                HStack(spacing: 16) {
                    Button(action: {
                        formRows.append(LotteryFormTemplateRow())
                        markCurrentTerminalDirty()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Row")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.cloudBlue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if rowToDelete != nil {
                            showingDeleteConfirmation = true
                        } else if !formRows.isEmpty {
                            rowToDelete = formRows.last
                            showingDeleteConfirmation = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "minus.circle.fill")
                            Text("Delete Row")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(rowToDelete != nil ? Color.red : Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(formRows.isEmpty)
                    
                    Spacer()
                }
                .padding()
                .background(Theme.cloudWhite)
                
                // Lottery Form Table - fits on screen
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Header Row
                        HStack(spacing: 0) {
                            headerCell("Bin #")
                            headerCell("Game #")
                            headerCell("Value")
                            headerCell("Tickets")
                            headerCell("Begin #")
                            headerCell("End #")
                            headerCell("Sold")
                            headerCell("Dollar")
                            headerCell("Books")
                        }
                        .background(Theme.cloudBlue.opacity(0.2))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.5)),
                            alignment: .bottom
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.5)),
                            alignment: .top
                        )
                        
                        // Data Rows
                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading template...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(Theme.cloudWhite)
                        } else if formRows.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No rows yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Tap 'Add Row' to create a new row")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(Theme.cloudWhite)
                        } else {
                            ForEach(Array($formRows.enumerated()), id: \.element.id) { index, $row in
                                HStack(spacing: 0) {
                                    // Bin# column - auto-populated with serial number (read-only)
                                    binNumberCell(String(index + 1))
                                    dataCell($row.gameNumber, rowIndex: index, isGameNumber: true)
                                    dataCell($row.value, isValueField: true)
                                    dataCell($row.tickets)
                                    dataCell($row.beginningNumber, onUpdate: {
                                        validateAndCalculateRow(for: index)
                                    }, rowIndex: index, isTicketNumber: true)
                                    dataCell($row.endingNumber, onUpdate: {
                                        validateAndCalculateRow(for: index)
                                    }, rowIndex: index, isTicketNumber: true)
                                    // Sold, Dollar, Books are read-only calculated cells
                                    calculatedCell(calculateSold(for: row))
                                    calculatedCell(calculateDollar(for: row))
                                    calculatedCell(calculateBooks(for: row))
                                }
                                .background(rowToDelete?.id == row.id ? Color.red.opacity(0.2) : Theme.cloudWhite)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.gray.opacity(0.5)),
                                    alignment: .bottom
                                )
                                .onTapGesture {
                                    if rowToDelete?.id == row.id {
                                        rowToDelete = nil
                                    } else {
                                        rowToDelete = row
                                    }
                                }
                            }
                            
                            // Totals Row (non-deletable)
                            HStack(spacing: 0) {
                                totalCell("", isBold: false) // Empty for Bin#
                                totalCell("TOTAL", isBold: true)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell("", isBold: false)
                                totalCell(formatNumber(totalSold), isBold: true)
                                totalCell(formatCurrency(totalDollars), isBold: true)
                                totalCell(formatNumber(totalBooks), isBold: true)
                            }
                            .background(Color(red: 0.9, green: 0.9, blue: 0.95))
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .foregroundColor(Theme.cloudBlue),
                                alignment: .top
                            )
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.gray.opacity(0.5)),
                                alignment: .bottom
                            )
                        }
                    }
                    .overlay(
                        // Left border for entire table
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .leading
                    )
                    .overlay(
                        // Right border for entire table
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(.gray.opacity(0.5)),
                        alignment: .trailing
                    )
                }
                .background(Theme.cloudWhite)
            }
        }
        .alert("Delete Row", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                rowToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let row = rowToDelete {
                    formRows.removeAll { $0.id == row.id }
                    rowToDelete = nil
                    markCurrentTerminalDirty()
                }
            }
        } message: {
            Text("Are you sure you want to delete this row?")
        }
        .onAppear {
            Task {
                await loadTemplate()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Validation", isPresented: $showingValidationMessage) {
            Button("OK") {
                validationMessage = nil
            }
        } message: {
            if let validationMessage = validationMessage {
                Text(validationMessage)
            }
        }
    }
    
    // MARK: - Terminal controls UI

    /// Stepper + tab strip + "archived" affordance. Shows in every
    /// location, but the tab strip and archived list collapse to
    /// nothing when the count is 1, so single-terminal locations see
    /// just a one-line stepper.
    @ViewBuilder
    private var terminalControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundColor(Theme.cloudBlue)
                Text("Lottery Terminals")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { terminalCount },
                        set: { newValue in
                            handleTerminalCountChange(to: newValue)
                        }
                    ),
                    in: 1...10
                ) {
                    Text("\(terminalCount) terminal\(terminalCount == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                }
                .labelsHidden()
                Text("\(terminalCount)")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 24)
                    .foregroundColor(.black)
            }
            .padding(.horizontal)

            // Tab strip — hidden entirely for single-terminal locations
            // so they see exactly today's UI (zero visual diff).
            if terminalCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...terminalCount, id: \.self) { terminal in
                            terminalTabPill(terminal: terminal)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Surface archived terminals so the manager knows raising
            // the count back will restore them. Only shows when there's
            // something archived (almost always empty for new locations).
            if !archivedTerminals.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Archived: \(archivedTerminals.sorted().map(String.init).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(Theme.cloudWhite)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .bottom
        )
    }

    private func terminalTabPill(terminal: Int) -> some View {
        let isSelected = terminal == selectedTerminal
        return Button(action: {
            Task { await selectTerminal(terminal) }
        }) {
            Text("Terminal \(terminal)")
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : Theme.cloudBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.cloudBlue : Theme.cloudBlue.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Theme.cloudBlue.opacity(isSelected ? 0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Apply a stepper change. Bumping up just expands the count and
    /// (if a previously-archived terminal slot is being re-exposed)
    /// removes it from the archive list — its old template + history
    /// come back into view automatically. Going down archives the
    /// trailing terminals so their data isn't lost.
    private func handleTerminalCountChange(to newValue: Int) {
        let oldValue = terminalCount
        guard newValue != oldValue, newValue >= 1 else { return }

        if newValue > oldValue {
            // If any terminals in the new range are archived, un-archive
            // them. (Tab strip will show them with their preserved data.)
            let unarchived = (oldValue + 1...newValue).filter { archivedTerminals.contains($0) }
            archivedTerminals.removeAll { unarchived.contains($0) }
        } else {
            // Going from 3 → 2 archives terminals 3...3 (the trailing
            // ones being dropped). Their template doc + history stay
            // in Firestore untouched.
            let toArchive = Array((newValue + 1)...oldValue)
            // De-duplicate against any pre-existing archive entries.
            archivedTerminals = Array(Set(archivedTerminals + toArchive)).sorted()
            // Drop drafts for the archived terminals so we don't write
            // them back on save.
            for n in toArchive { terminalDrafts.removeValue(forKey: n) }
            // If we were editing an about-to-be-archived terminal,
            // bounce back to terminal 1.
            if selectedTerminal > newValue {
                Task { await selectTerminal(1) }
            }
            didReduceTerminals = true
        }

        terminalCount = newValue
    }

    // MARK: - Terminal-aware load / save

    /// Initial load. Reads the location's current terminal config and
    /// pulls terminal 1's template (always — every location has at
    /// least one). Terminals 2+ are loaded lazily as the manager
    /// switches tabs to them.
    private func loadTemplate() async {
        isLoading = true

        let location = viewModel.location
        terminalCount = location?.effectiveLotteryTerminalCount ?? 1
        archivedTerminals = location?.lotteryArchivedTerminals ?? []
        selectedTerminal = 1

        let draft = await loadDraft(for: 1)
        terminalDrafts[1] = draft
        applyDraftToFields(draft)

        isLoading = false
    }

    /// Fetch a single terminal's template from Firestore and convert
    /// it into a `TerminalDraft`. Returns an empty draft when nothing
    /// exists yet (e.g. the manager just bumped the count from 2 to 5
    /// and terminal 5 has never been configured).
    private func loadDraft(for terminal: Int) async -> TerminalDraft {
        let result: (rows: [LotteryFormTemplateRow], lotteryRegisterAmount: String, reverseOrder: Bool)
        if terminal == 1 {
            // Terminal 1 lives at the legacy doc id `template`, so we
            // route through the original (unparametered) helper —
            // identical wire calls to pre-multi-terminal code.
            result = await viewModel.loadLotteryFormTemplate()
        } else {
            result = await viewModel.loadLotteryFormTemplate(terminalNumber: terminal)
        }

        var draft = TerminalDraft(
            rows: result.rows,
            lotteryRegisterAmount: result.lotteryRegisterAmount,
            reverseOrder: result.reverseOrder
        )

        // Pre-calculate sold/dollars/books so the totals row is right
        // immediately on tab switch without waiting for an edit.
        for index in draft.rows.indices {
            calculateRowValues(for: index, in: &draft)
        }

        draft.isDirty = false
        return draft
    }

    /// Push the current `formRows`/`lotteryRegisterAmount`/
    /// `reverseOrder` UI state into the in-memory draft for the given
    /// terminal. Called right before switching tabs (or saving) so we
    /// don't lose the manager's edits.
    private func captureCurrentTerminalDraft() {
        var draft = terminalDrafts[selectedTerminal] ?? TerminalDraft()
        // Treat anything captured as already-known dirty if the
        // existing draft was; otherwise we leave it alone.
        let wasDirty = draft.isDirty
        draft.rows = formRows
        draft.lotteryRegisterAmount = lotteryRegisterAmount
        draft.reverseOrder = reverseOrder
        draft.isDirty = wasDirty
        terminalDrafts[selectedTerminal] = draft
    }

    /// Pull the in-memory draft for the given terminal into the
    /// editable UI fields. Called when the manager taps a different
    /// terminal in the tab strip.
    private func applyDraftToFields(_ draft: TerminalDraft) {
        formRows = draft.rows
        lotteryRegisterAmount = draft.lotteryRegisterAmount
        reverseOrder = draft.reverseOrder
        rowToDelete = nil
    }

    /// Mark whatever terminal is currently in the editor as dirty so
    /// `saveTemplate()` knows it needs writing back to Firestore.
    private func markCurrentTerminalDirty() {
        // Avoid mutating during initial load (would prematurely
        // dirty a draft we just fetched verbatim).
        guard !isLoading else { return }
        var draft = terminalDrafts[selectedTerminal] ?? TerminalDraft()
        draft.rows = formRows
        draft.lotteryRegisterAmount = lotteryRegisterAmount
        draft.reverseOrder = reverseOrder
        draft.isDirty = true
        terminalDrafts[selectedTerminal] = draft
    }

    /// Switch the editor to a different terminal: capture the current
    /// one's edits, then either restore that terminal from cache or
    /// fetch it from Firestore.
    private func selectTerminal(_ terminal: Int) async {
        guard terminal != selectedTerminal else { return }
        captureCurrentTerminalDraft()
        selectedTerminal = terminal
        if let cached = terminalDrafts[terminal] {
            applyDraftToFields(cached)
        } else {
            isLoading = true
            let draft = await loadDraft(for: terminal)
            terminalDrafts[terminal] = draft
            applyDraftToFields(draft)
            isLoading = false
        }
    }

    /// Save everything dirty. The order matters:
    ///   1. Capture the currently-visible terminal's edits into the
    ///      drafts dictionary.
    ///   2. Write each dirty terminal's template (parallelisable, but
    ///      kept sequential for simpler error reporting).
    ///   3. Update the location's `lotteryTerminalCount` +
    ///      `lotteryArchivedTerminals` last so the count never refers
    ///      to terminals that haven't been written yet.
    private func saveTemplate() async {
        isSaving = true
        errorMessage = nil
        showingError = false
        captureCurrentTerminalDraft()

        do {
            for (terminal, draft) in terminalDrafts where draft.isDirty {
                // Preserve the legacy single-terminal doc shape: when
                // the location has only one terminal we route through
                // the original (unparametered) save helper, which
                // doesn't attach a `terminalNumber` field. That keeps
                // existing single-terminal Firestore docs byte-for-byte
                // identical to how they looked before multi-terminal
                // support shipped (no new fields added to legacy data).
                if terminalCount == 1 && terminal == 1 {
                    try await viewModel.saveLotteryFormTemplate(
                        rows: draft.rows,
                        lotteryRegisterAmount: draft.lotteryRegisterAmount,
                        reverseOrder: draft.reverseOrder
                    )
                } else {
                    try await viewModel.saveLotteryFormTemplate(
                        terminalNumber: terminal,
                        rows: draft.rows,
                        lotteryRegisterAmount: draft.lotteryRegisterAmount,
                        reverseOrder: draft.reverseOrder
                    )
                }
            }

            // Persist the new terminal count + archive list. We only
            // touch this if it actually changed to avoid noisy writes.
            let location = viewModel.location
            let storedCount = location?.effectiveLotteryTerminalCount ?? 1
            let storedArchived = location?.lotteryArchivedTerminals ?? []
            if terminalCount != storedCount || archivedTerminals != storedArchived {
                try await viewModel.updateLotteryTerminalCount(
                    newCount: terminalCount,
                    archived: archivedTerminals
                )
            }

            isSaving = false
            dismiss()
        } catch {
            errorMessage = "Failed to save template: \(error.localizedDescription)"
            showingError = true
            isSaving = false
        }
    }

    /// Variant of `calculateRowValues` that takes the draft by
    /// reference, so we can pre-fill calculated columns without
    /// touching the live `formRows` state.
    private func calculateRowValues(for index: Int, in draft: inout TerminalDraft) {
        guard index < draft.rows.count else { return }
        let row = draft.rows[index]
        let hasValue = !row.value.isEmpty
        let hasTickets = !row.tickets.isEmpty
        let hasBeginning = !row.beginningNumber.isEmpty
        let hasEnding = !row.endingNumber.isEmpty
        guard hasValue && hasTickets && hasBeginning && hasEnding else {
            draft.rows[index].sold = ""
            draft.rows[index].dollar = ""
            draft.rows[index].books = ""
            return
        }
        let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: draft.reverseOrder
        )
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        draft.rows[index].sold = String(sold)
        draft.rows[index].dollar = String(dollars)
        draft.rows[index].books = String(books)
    }
    
    private var columnWidth: CGFloat {
        // Calculate width to fit 9 columns on screen
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 16 // Side padding
        let availableWidth = screenWidth - padding * 2
        return availableWidth / 9
    }
    
    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.black)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudBlue.opacity(0.1))
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border (only for first cell)
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func binNumberCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func dataCell(_ binding: Binding<String>, onUpdate: (() -> Void)? = nil, rowIndex: Int? = nil, isTicketNumber: Bool = false, isGameNumber: Bool = false, isValueField: Bool = false) -> some View {
        TextField("", text: Binding(
            get: { 
                if isValueField {
                    // Display with $ sign, but store without
                    let value = binding.wrappedValue
                    if value.isEmpty {
                        return ""
                    }
                    // Remove $ if present, then add it back for display
                    let cleanValue = value.replacingOccurrences(of: "$", with: "")
                    return cleanValue.isEmpty ? "" : "$\(cleanValue)"
                }
                return binding.wrappedValue
            },
            set: { newValue in
                // For value field, remove $ sign before processing
                var cleanValue = newValue
                if isValueField {
                    cleanValue = cleanValue.replacingOccurrences(of: "$", with: "")
                }
                
                // Only allow numeric characters and single decimal point
                var filtered = ""
                var hasDecimal = false
                for char in cleanValue {
                    if char.isNumber {
                        filtered.append(char)
                    } else if char == "." && !hasDecimal {
                        filtered.append(char)
                        hasDecimal = true
                    }
                }
                
                // Normalize "0" to "00" for ticket number fields (since "0" represents the first ticket)
                if isTicketNumber && filtered == "0" {
                    filtered = "00"
                }
                
                // Validate ticket number range (prevent invalid entry, but don't show alert)
                if isTicketNumber, let index = rowIndex, index < formRows.count {
                    let row = formRows[index]
                    if !filtered.isEmpty && filtered != "00" {
                        // Check if tickets value exists
                        if let ticketsInt = Int(row.tickets), ticketsInt > 0 {
                            let maxTicketNumber = ticketsInt - 1
                            if let enteredNum = Int(filtered), enteredNum > maxTicketNumber {
                                // Don't update the value (silently prevent invalid entry)
                                return
                            }
                        }
                    }
                }
                
                binding.wrappedValue = filtered
                // Trigger calculation update
                onUpdate?()
                
                // If this is a game number field, trigger auto-population after a short delay
                if isGameNumber {
                    Task {
                        // Small delay to allow the value to be set
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        if let index = rowIndex, index < formRows.count {
                            await autoPopulateFromGameDatabase(for: index)
                        }
                    }
                }
            }
        ))
        .keyboardType(.decimalPad)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 11))
        .foregroundColor(.black)
        .frame(width: columnWidth, height: 44)
        .background(Theme.cloudWhite)
        .overlay(
            // Right border
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .trailing
        )
        .overlay(
            // Left border (only for first cell)
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.gray.opacity(0.5)),
            alignment: .leading
        )
    }
    
    // Read-only calculated cell
    private func calculatedCell(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Theme.cloudWhite)
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    private func totalCell(_ text: String, isBold: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: isBold ? .bold : .regular))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(width: columnWidth, height: 44)
            .background(Color(red: 0.9, green: 0.9, blue: 0.95))
            .overlay(
                // Right border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .trailing
            )
            .overlay(
                // Left border
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.5)),
                alignment: .leading
            )
    }
    
    // Calculate values for a specific row (no validation alerts during entry).
    // Also marks the current terminal as dirty since this fires on
    // every cell edit — that means every keystroke that might change
    // a value flips the dirty bit. Cheap, and avoids a separate
    // expensive `formRows` equality check.
    private func validateAndCalculateRow(for index: Int) {
        guard index < formRows.count else { return }
        markCurrentTerminalDirty()
        let row = formRows[index]
        
        // Check if Value and Tickets are present
        let hasValue = !row.value.isEmpty
        let hasTickets = !row.tickets.isEmpty
        let hasBeginning = !row.beginningNumber.isEmpty
        let hasEnding = !row.endingNumber.isEmpty
        
        // Only calculate if we have all required fields
        // No validation alerts - just skip calculation if fields are missing
        guard hasValue && hasTickets && hasBeginning && hasEnding else {
            // Clear calculated values if missing required fields
            formRows[index].sold = ""
            formRows[index].dollar = ""
            formRows[index].books = ""
            return
        }
        
        // Calculate sold and books
        let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        
        // Calculate dollars
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        
        // Update row values (these are stored but not displayed - we calculate on the fly)
        formRows[index].sold = String(sold)
        formRows[index].dollar = String(dollars)
        formRows[index].books = String(books)
    }
    
    // Calculate values for a specific row (without validation, for display)
    private func calculateRowValues(for index: Int) {
        guard index < formRows.count else { return }
        let row = formRows[index]
        
        // Only calculate if we have all required fields
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return
        }
        
        // Calculate sold and books
        let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        
        // Calculate dollars
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        
        // Update row values (these are stored but not displayed - we calculate on the fly)
        formRows[index].sold = String(sold)
        formRows[index].dollar = String(dollars)
        formRows[index].books = String(books)
    }
    
    // Calculate sold for a row (for display)
    private func calculateSold(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        return sold > 0 ? String(sold) : ""
    }
    
    // Calculate dollar for a row (for display)
    private func calculateDollar(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
        return dollars > 0 ? formatCurrency(Double(dollars)) : ""
    }
    
    // Calculate books for a row (for display)
    private func calculateBooks(for row: LotteryFormTemplateRow) -> String {
        // Only calculate if Value and Tickets are present
        guard !row.value.isEmpty && !row.tickets.isEmpty && !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty else {
            return ""
        }
        
        let (_, books) = LotteryCalculationService.calculateSoldAndBooks(
            beginning: row.beginningNumber,
            ending: row.endingNumber,
            tickets: row.tickets,
            reverseOrder: reverseOrder
        )
        return books > 0 ? String(books) : ""
    }
    
    // Computed properties for totals - only include rows with valid data
    private var totalSold: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, and tickets
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty else {
                return total
            }
            
            let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            return total + Double(sold)
        }
    }
    
    private var totalDollars: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, tickets, and value
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty,
                  !row.value.isEmpty else {
                return total
            }
            
            let (sold, _) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            let dollars = LotteryCalculationService.calculateDollars(sold: sold, value: row.value)
            return total + Double(dollars)
        }
    }
    
    private var totalBooks: Double {
        formRows.reduce(0.0) { total, row in
            // Only calculate if row has beginning, ending, and tickets
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty else {
                return total
            }
            
            let (_, books) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            return total + Double(books)
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value == 0 {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }
    
    private func formatCurrency(_ value: Double) -> String {
        if value == 0 {
            return ""
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: value)) ?? ""
        return formatted.isEmpty ? "" : "$\(formatted)"
    }
    
    // Auto-populate Value and Tickets from game database when game number is entered
    private func autoPopulateFromGameDatabase(for index: Int) async {
        guard index < formRows.count else { return }
        let gameNumber = formRows[index].gameNumber
        
        // Only fetch if game number is not empty
        guard !gameNumber.isEmpty else { return }
        
        do {
            let gameData = try await FirebaseService.shared.fetchGameData(gameNumber: gameNumber)
            
            await MainActor.run {
                if let gameData = gameData {
                    // Auto-populate value and tickets
                    formRows[index].value = gameData.value
                    formRows[index].tickets = gameData.tickets
                    
                    // Recalculate row values
                    calculateRowValues(for: index)
                }
            }
        } catch {
            // Game number not found in database - silently ignore
            print("Game number \(gameNumber) not found in database")
        }
    }
}

#Preview {
    LotteryCustomizationView(viewModel: LocationDetailViewModel(userId: "test", locationId: "test"))
}

