//
//  ReceivablesView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ReceivablesView: View {
    let userId: String
    let locationId: String
    @State private var receivables: [Receivable] = []
    @State private var isLoading = false
    @State private var showingAddReceivable = false
    @State private var showingHistory = false
    @State private var errorMessage: String?
    @State private var receivableToDelete: Receivable?
    @State private var showingDeleteConfirmation = false
    @State private var duplicateGroupsToClean: [[Receivable]] = []
    @State private var showingCleanupConfirmation = false
    @State private var cleanupResultMessage: String?
    @State private var isSelectionMode = false
    @State private var selectedReceivableIds: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingRecurringDeletePrompt = false
    
    private var activeReceivables: [Receivable] {
        receivables.filter { !$0.isReceived }
    }
    
    private var receivedReceivables: [Receivable] {
        receivables.filter { $0.isReceived }.sorted { ($0.receivedAt ?? Date.distantPast) > ($1.receivedAt ?? Date.distantPast) }
    }
    
    private var totalReceivables: Double {
        activeReceivables.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                VStack(spacing: 0) {
                    // Total Card
                    VStack(spacing: 12) {
                        Text("Total Receivables")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(formatCurrency(totalReceivables))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Theme.cloudBlue.opacity(0.8))
                    
                    // Toggle between Active and History
                    Picker("View", selection: $showingHistory) {
                        Text("Active").tag(false)
                        Text("History").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // List — must be a List (not a LazyVStack/ScrollView) for
                    // .swipeActions to actually fire. listRowBackground/Separator
                    // tweaks keep the existing card-on-gradient look intact.
                    List {
                        if showingHistory {
                            ForEach(receivedReceivables) { receivable in
                                receivableListItem(receivable: receivable, showHistory: true)
                            }
                        } else {
                            ForEach(activeReceivables) { receivable in
                                receivableListItem(receivable: receivable, showHistory: false)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Receivables")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        prepareDuplicateCleanup()
                    }) {
                        Label("Clean Up Duplicates", systemImage: "wand.and.stars")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $showingAddReceivable) {
            AddReceivableView(userId: userId, locationId: locationId) {
                Task {
                    await loadReceivables()
                }
            }
        }
        .alert("Delete Receivable", isPresented: $showingDeleteConfirmation, presenting: receivableToDelete) { receivable in
            Button("Cancel", role: .cancel) {
                receivableToDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteReceivable(receivable)
                    receivableToDelete = nil
                }
            }
        } message: { receivable in
            Text("Are you sure you want to delete the receivable from '\(receivable.receiveFrom)' for \(formatCurrency(receivable.amount))? This cannot be undone.")
        }
        .alert("Delete \(selectedReceivableIds.count) Item\(selectedReceivableIds.count == 1 ? "" : "s")", isPresented: $showingBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await performBulkDelete(deleteEntireSeries: false)
                }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedReceivableIds.count) receivable\(selectedReceivableIds.count == 1 ? "" : "s")? This cannot be undone.")
        }
        .confirmationDialog(
            "Some Selected Items Are Recurring",
            isPresented: $showingRecurringDeletePrompt,
            titleVisibility: .visible
        ) {
            Button("Delete Only These \(selectedReceivableIds.count) Item\(selectedReceivableIds.count == 1 ? "" : "s")", role: .destructive) {
                Task {
                    await performBulkDelete(deleteEntireSeries: false)
                }
            }
            let seriesCount = countItemsInSelectedRecurringSeries()
            Button("Delete Entire Recurring Series (\(seriesCount) item\(seriesCount == 1 ? "" : "s"))", role: .destructive) {
                Task {
                    await performBulkDelete(deleteEntireSeries: true)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether to delete only the selected items, or to delete every receivable in the same recurring series (past, present, and future).")
        }
        .alert("Clean Up Duplicates", isPresented: $showingCleanupConfirmation) {
            Button("Cancel", role: .cancel) {
                duplicateGroupsToClean = []
            }
            Button("Clean Up", role: .destructive) {
                Task {
                    await performDuplicateCleanup()
                }
            }
        } message: {
            let duplicateCount = duplicateGroupsToClean.reduce(0) { $0 + max(0, $1.count - 1) }
            if duplicateCount == 0 {
                Text("No duplicate receivables found.")
            } else {
                Text("Found \(duplicateCount) duplicate receivable\(duplicateCount == 1 ? "" : "s") across \(duplicateGroupsToClean.count) recurring item\(duplicateGroupsToClean.count == 1 ? "" : "s"). Delete the duplicates? Received items will be preserved when possible.")
            }
        }
        .alert("Cleanup Complete", isPresented: .constant(cleanupResultMessage != nil)) {
            Button("OK") {
                cleanupResultMessage = nil
            }
        } message: {
            if let message = cleanupResultMessage {
                Text(message)
            }
        }
        .task {
            await loadReceivables()
        }
    }
    
    // MARK: - List item builder
    // Two completely separate branches so that in normal mode there is NO
    // .onTapGesture on the row — an outer tap gesture intercepts taps before
    // they reach the inner Button (the "Received" pill), making it no-op.
    @ViewBuilder
    private func receivableListItem(receivable: Receivable, showHistory: Bool) -> some View {
        let isSelected = selectedReceivableIds.contains(receivable.id)
        if isSelectionMode {
            ReceivableRow(
                receivable: receivable,
                onDelete: nil,
                onMarkReceived: nil,
                showHistory: showHistory,
                isSelectionMode: true,
                isSelected: isSelected
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(receivable)
            }
        } else {
            ReceivableRow(
                receivable: receivable,
                onDelete: nil,
                onMarkReceived: showHistory ? nil : {
                    Task { await markAsReceived(receivable) }
                },
                showHistory: showHistory,
                isSelectionMode: false,
                isSelected: false
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    receivableToDelete = receivable
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Bottom action bar
    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            if isSelectionMode {
                // Cancel — red cross (left)
                Button(action: exitSelectionMode) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                
                Spacer()
                
                Text("\(selectedReceivableIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Confirm delete — green tick (right)
                Button(action: handleBulkDeleteTapped) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(selectedReceivableIds.isEmpty ? Color.gray.opacity(0.5) : Color.green)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(selectedReceivableIds.isEmpty)
            } else {
                Button(action: enterSelectionMode) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(receivables.isEmpty)
                .opacity(receivables.isEmpty ? 0.4 : 1)
                
                Spacer()
                
                Button(action: { showingAddReceivable = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.cloudBlue)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Selection-mode helpers
    private func enterSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = true
            selectedReceivableIds = []
        }
    }
    
    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = false
            selectedReceivableIds = []
        }
    }
    
    private func toggleSelection(_ receivable: Receivable) {
        if selectedReceivableIds.contains(receivable.id) {
            selectedReceivableIds.remove(receivable.id)
        } else {
            selectedReceivableIds.insert(receivable.id)
        }
    }
    
    private var selectedReceivables: [Receivable] {
        receivables.filter { selectedReceivableIds.contains($0.id) }
    }
    
    private func countItemsInSelectedRecurringSeries() -> Int {
        let recurringSelected = selectedReceivables.filter { $0.frequency != .none }
        let chainKeys = Set(recurringSelected.map { chainKey(for: $0) })
        let nonRecurringSelected = selectedReceivables.filter { $0.frequency == .none }
        let chainItems = receivables.filter { chainKeys.contains(chainKey(for: $0)) }
        return chainItems.count + nonRecurringSelected.count
    }
    
    private func handleBulkDeleteTapped() {
        guard !selectedReceivableIds.isEmpty else { return }
        let recurringSelected = selectedReceivables.filter { $0.frequency != .none }
        if recurringSelected.isEmpty {
            showingBulkDeleteConfirmation = true
        } else {
            showingRecurringDeletePrompt = true
        }
    }
    
    private func performBulkDelete(deleteEntireSeries: Bool) async {
        var idsToDelete: Set<String> = []
        
        if deleteEntireSeries {
            let recurringSelected = selectedReceivables.filter { $0.frequency != .none }
            let chainKeys = Set(recurringSelected.map { chainKey(for: $0) })
            for receivable in receivables where chainKeys.contains(chainKey(for: receivable)) {
                idsToDelete.insert(receivable.id)
            }
            for receivable in selectedReceivables where receivable.frequency == .none {
                idsToDelete.insert(receivable.id)
            }
        } else {
            idsToDelete = selectedReceivableIds
        }
        
        var errorCount = 0
        for id in idsToDelete {
            do {
                try await FirebaseService.shared.deleteReceivable(
                    userId: userId,
                    locationId: locationId,
                    receivableId: id
                )
            } catch {
                errorCount += 1
                print("Failed to delete receivable \(id): \(error.localizedDescription)")
            }
        }
        
        if errorCount > 0 {
            errorMessage = "Failed to delete \(errorCount) item\(errorCount == 1 ? "" : "s")."
        }
        
        exitSelectionMode()
        await loadReceivables()
    }
    
    private func loadReceivables() async {
        isLoading = true
        errorMessage = nil
        do {
            receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: locationId)
            // Check and create recurring items
            await checkAndCreateRecurringReceivables()
            // Reload to get any newly created items
            receivables = try await FirebaseService.shared.fetchReceivables(userId: userId, locationId: locationId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func deleteReceivable(_ receivable: Receivable) async {
        do {
            try await FirebaseService.shared.deleteReceivable(userId: userId, locationId: locationId, receivableId: receivable.id)
            await loadReceivables()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func markAsReceived(_ receivable: Receivable) async {
        do {
            let updatedReceivable = Receivable(
                id: receivable.id,
                locationId: receivable.locationId,
                receiveFrom: receivable.receiveFrom,
                amount: receivable.amount,
                dueDate: receivable.dueDate,
                createdAt: receivable.createdAt,
                notes: receivable.notes,
                frequency: receivable.frequency,
                isReceived: true,
                receivedAt: Date(),
                originalReceivableId: receivable.originalReceivableId
            )
            try await FirebaseService.shared.updateReceivable(userId: userId, locationId: locationId, receivable: updatedReceivable)
            
            // If it's a recurring item, schedule the next occurrence
            if receivable.frequency != .none, let dueDate = receivable.dueDate {
                await scheduleNextRecurringReceivable(receivable: receivable, dueDate: dueDate)
            }
            
            await loadReceivables()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // Identifies the recurring chain a receivable belongs to.
    // The very first receivable in a chain has no `originalReceivableId`, so its
    // own id is the chain key; every child copies that id forward.
    private func chainKey(for receivable: Receivable) -> String {
        receivable.originalReceivableId ?? receivable.id
    }
    
    // Returns true if any receivable in the same chain already has a due date
    // within ±1 day of `targetDate` (received OR not). Used to prevent the
    // auto-spawn logic from creating duplicates.
    private func hasItemInChain(chainKey: String, near targetDate: Date) -> Bool {
        let calendar = Calendar.current
        return receivables.contains { r in
            self.chainKey(for: r) == chainKey &&
            abs(calendar.dateComponents([.day], from: r.dueDate ?? Date(), to: targetDate).day ?? 999) <= 1
        }
    }
    
    private func scheduleNextRecurringReceivable(receivable: Receivable, dueDate: Date) async {
        let calendar = Calendar.current
        var nextDueDate: Date?
        
        switch receivable.frequency {
        case .weekly:
            nextDueDate = calendar.date(byAdding: .weekOfYear, value: 1, to: dueDate)
        case .monthly:
            nextDueDate = calendar.date(byAdding: .month, value: 1, to: dueDate)
        case .none:
            return
        }
        
        guard let nextDate = nextDueDate else { return }
        
        // Don't create a duplicate if this chain already has an item near this date.
        if hasItemInChain(chainKey: chainKey(for: receivable), near: nextDate) { return }
        
        // Create new receivable 5 days before the next due date
        let createDate = calendar.date(byAdding: .day, value: -5, to: nextDate) ?? nextDate
        
        // Only create if we're at or past the create date (5 days before due date)
        let now = Date()
        if now >= createDate {
            let newReceivable = Receivable(
                locationId: locationId,
                receiveFrom: receivable.receiveFrom,
                amount: receivable.amount,
                dueDate: nextDate,
                notes: receivable.notes,
                frequency: receivable.frequency,
                originalReceivableId: receivable.originalReceivableId ?? receivable.id
            )
            
            do {
                try await FirebaseService.shared.saveReceivable(userId: userId, locationId: locationId, receivable: newReceivable)
            } catch {
                print("Error creating next recurring receivable: \(error.localizedDescription)")
            }
        }
    }
    
    // Check and create recurring items that should appear 5 days before due date.
    // Only the *latest* received receivable in each chain seeds the next cycle —
    // otherwise older received items each try to spawn duplicates of cycles that
    // have already advanced past them.
    private func checkAndCreateRecurringReceivables() async {
        let calendar = Calendar.current
        let now = Date()
        
        // Group received recurring receivables by chain, keeping only the one
        // with the most recent due date per chain.
        let receivedRecurring = receivables.filter { $0.isReceived && $0.frequency != .none }
        var latestReceivedByChain: [String: Receivable] = [:]
        for received in receivedRecurring {
            let key = chainKey(for: received)
            if let existing = latestReceivedByChain[key] {
                let existingDue = existing.dueDate ?? .distantPast
                let candidateDue = received.dueDate ?? .distantPast
                if candidateDue > existingDue {
                    latestReceivedByChain[key] = received
                }
            } else {
                latestReceivedByChain[key] = received
            }
        }
        
        for receivedReceivable in latestReceivedByChain.values {
            guard let originalDueDate = receivedReceivable.dueDate else { continue }
            
            // Calculate next due date based on frequency
            var nextDueDate: Date?
            switch receivedReceivable.frequency {
            case .weekly:
                nextDueDate = calendar.date(byAdding: .weekOfYear, value: 1, to: originalDueDate)
            case .monthly:
                nextDueDate = calendar.date(byAdding: .month, value: 1, to: originalDueDate)
            case .none:
                continue
            }
            
            guard let nextDate = nextDueDate else { continue }
            
            // Skip if this chain already has any item (received or not) at the next date.
            if hasItemInChain(chainKey: chainKey(for: receivedReceivable), near: nextDate) { continue }
            
            // Check if we should create a new one (5 days before due date)
            let createDate = calendar.date(byAdding: .day, value: -5, to: nextDate) ?? nextDate
            
            if now >= createDate {
                let newReceivable = Receivable(
                    locationId: locationId,
                    receiveFrom: receivedReceivable.receiveFrom,
                    amount: receivedReceivable.amount,
                    dueDate: nextDate,
                    notes: receivedReceivable.notes,
                    frequency: receivedReceivable.frequency,
                    originalReceivableId: receivedReceivable.originalReceivableId ?? receivedReceivable.id
                )
                
                do {
                    try await FirebaseService.shared.saveReceivable(userId: userId, locationId: locationId, receivable: newReceivable)
                } catch {
                    print("Error creating recurring receivable: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    // Identify duplicate receivables — same recurring chain + same due-date day.
    // The first item in each returned group is the one to keep; the rest are duplicates.
    private func findDuplicateGroups() -> [[Receivable]] {
        let calendar = Calendar.current
        var grouped: [String: [Receivable]] = [:]
        for receivable in receivables {
            let chain = chainKey(for: receivable)
            let dayKey: String
            if let due = receivable.dueDate {
                let day = calendar.startOfDay(for: due)
                dayKey = "\(day.timeIntervalSince1970)"
            } else {
                dayKey = "no-date"
            }
            let key = "\(chain)|\(dayKey)"
            grouped[key, default: []].append(receivable)
        }
        
        return grouped.values
            .filter { $0.count > 1 }
            .map { group in
                group.sorted { lhs, rhs in
                    if lhs.isReceived != rhs.isReceived { return lhs.isReceived && !rhs.isReceived }
                    if lhs.isReceived && rhs.isReceived {
                        return (lhs.receivedAt ?? .distantPast) > (rhs.receivedAt ?? .distantPast)
                    }
                    return lhs.createdAt > rhs.createdAt
                }
            }
    }
    
    private func prepareDuplicateCleanup() {
        duplicateGroupsToClean = findDuplicateGroups()
        showingCleanupConfirmation = true
    }
    
    private func performDuplicateCleanup() async {
        var deletedCount = 0
        var errorCount = 0
        
        for group in duplicateGroupsToClean {
            for duplicate in group.dropFirst() {
                do {
                    try await FirebaseService.shared.deleteReceivable(
                        userId: userId,
                        locationId: locationId,
                        receivableId: duplicate.id
                    )
                    deletedCount += 1
                } catch {
                    errorCount += 1
                    print("Failed to delete duplicate receivable \(duplicate.id): \(error.localizedDescription)")
                }
            }
        }
        
        duplicateGroupsToClean = []
        await loadReceivables()
        
        if deletedCount == 0 && errorCount == 0 {
            cleanupResultMessage = "No duplicates were removed."
        } else if errorCount > 0 {
            cleanupResultMessage = "Removed \(deletedCount) duplicate\(deletedCount == 1 ? "" : "s"). \(errorCount) failed."
        } else {
            cleanupResultMessage = "Removed \(deletedCount) duplicate receivable\(deletedCount == 1 ? "" : "s")."
        }
    }
}

struct ReceivableRow: View {
    let receivable: Receivable
    let onDelete: (() -> Void)?
    let onMarkReceived: (() -> Void)?
    let showHistory: Bool
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    
    // Compared at start-of-day so a receivable "due today" isn't overdue until tomorrow.
    private var isOverdue: Bool {
        guard let dueDate = receivable.dueDate, !receivable.isReceived else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: Date())
    }
    
    private var daysLate: Int {
        guard let dueDate = receivable.dueDate else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: Date())
        )
        return max(0, components.day ?? 0)
    }
    
    private var receivedLateDays: Int {
        guard let dueDate = receivable.dueDate, let receivedAt = receivable.receivedAt else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: receivedAt)
        )
        return max(0, components.day ?? 0)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Theme.cloudBlue : Color.gray.opacity(0.5))
                    .transition(.opacity.combined(with: .scale))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(receivable.receiveFrom)
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        if isOverdue {
                            Text("MISSED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                    }
                    
                    if receivable.frequency != .none {
                        Text(receivable.frequency.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    if let dueDate = receivable.dueDate {
                        if isOverdue {
                            Text("Due: \(dueDate, formatter: dateFormatter) · \(daysLate) day\(daysLate == 1 ? "" : "s") late")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        } else {
                            Text("Due: \(dueDate, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                    }
                    
                    if showHistory, let receivedAt = receivable.receivedAt {
                        HStack(spacing: 6) {
                            Text("Received: \(receivedAt, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.green)
                            if receivedLateDays > 0 {
                                Text("(\(receivedLateDays) day\(receivedLateDays == 1 ? "" : "s") late)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    if let notes = receivable.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(Theme.darkGray)
                    }
                }
                
                Spacer()
                
                Text(formatCurrency(receivable.amount))
                    .font(.headline)
                    .foregroundColor(.green)
                
                if !showHistory && !isSelectionMode {
                    if let onMarkReceived = onMarkReceived {
                        Button(action: onMarkReceived) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                Text("Received")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Theme.cloudWhite)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelectionMode && isSelected ? Theme.cloudBlue :
                        isOverdue ? Color.red : Color.clear,
                        lineWidth: 2
                    )
            )
            .opacity(showHistory ? 0.7 : 1.0)
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

struct AddReceivableView: View {
    let userId: String
    let locationId: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var receiveFrom = ""
    @State private var amount = ""
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var frequency: RecurringFrequency = .none
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Receivable Details") {
                        TextField("Receive From", text: $receiveFrom)
                            .textInputAutocapitalization(.words)
                        
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                        
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                        
                        Toggle("Set Due Date", isOn: $hasDueDate)
                        
                        if hasDueDate {
                            DatePicker("Due Date", selection: $selectedDate, displayedComponents: .date)
                        }
                        
                        TextField("Notes (Optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Add Receivable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveReceivable()
                        }
                    }
                    .disabled(receiveFrom.isEmpty || amount.isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func saveReceivable() async {
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }
        
        isSaving = true
        do {
            let receivable = Receivable(
                locationId: locationId,
                receiveFrom: receiveFrom,
                amount: amountValue,
                dueDate: hasDueDate ? selectedDate : nil,
                notes: notes.isEmpty ? nil : notes,
                frequency: frequency
            )
            try await FirebaseService.shared.saveReceivable(userId: userId, locationId: locationId, receivable: receivable)
            dismiss()
            onSave()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

