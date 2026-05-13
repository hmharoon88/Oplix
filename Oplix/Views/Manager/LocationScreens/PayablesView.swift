//
//  PayablesView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct PayablesView: View {
    let userId: String
    let locationId: String
    @State private var payables: [Payable] = []
    @State private var isLoading = false
    @State private var showingAddPayable = false
    @State private var showingHistory = false
    @State private var errorMessage: String?
    @State private var payableToDelete: Payable?
    @State private var showingDeleteConfirmation = false
    @State private var duplicateGroupsToClean: [[Payable]] = []
    @State private var showingCleanupConfirmation = false
    @State private var cleanupResultMessage: String?
    @State private var isSelectionMode = false
    @State private var selectedPayableIds: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingRecurringDeletePrompt = false
    // Driving the edit sheet by an Identifiable value avoids the "stale binding"
    // problem you'd get with a parallel Bool + payable pair (the sheet would
    // otherwise capture an outdated payable on rapid taps).
    @State private var payableToEdit: Payable?
    
    private var activePayables: [Payable] {
        payables.filter { !$0.isPaid }
    }
    
    private var paidPayables: [Payable] {
        payables.filter { $0.isPaid }.sorted { ($0.paidAt ?? Date.distantPast) > ($1.paidAt ?? Date.distantPast) }
    }
    
    private var totalPayables: Double {
        activePayables.reduce(0) { $0 + $1.amount }
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
                        Text("Total Payables")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(formatCurrency(totalPayables))
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
                    .oplixSegmentedPickerTint()
                    .padding(.horizontal)
                    .padding(.top, 12)
                    
                    // List — must be a List (not a LazyVStack/ScrollView) for
                    // .swipeActions to actually fire. listRowBackground/Separator
                    // tweaks keep the existing card-on-gradient look intact.
                    List {
                        if showingHistory {
                            ForEach(paidPayables) { payable in
                                payableListItem(payable: payable, showHistory: true)
                            }
                        } else {
                            ForEach(activePayables) { payable in
                                payableListItem(payable: payable, showHistory: false)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Payables")
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
        .sheet(isPresented: $showingAddPayable) {
            AddPayableView(userId: userId, locationId: locationId) {
                Task {
                    await loadPayables()
                }
            }
        }
        .sheet(item: $payableToEdit) { payable in
            AddPayableView(
                userId: userId,
                locationId: locationId,
                existing: payable,
                siblings: payables
            ) {
                Task {
                    await loadPayables()
                }
            }
        }
        .alert("Delete Payable", isPresented: $showingDeleteConfirmation, presenting: payableToDelete) { payable in
            Button("Cancel", role: .cancel) {
                payableToDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    await deletePayable(payable)
                    payableToDelete = nil
                }
            }
        } message: { payable in
            Text("Are you sure you want to delete the payable to '\(payable.payTo)' for \(formatCurrency(payable.amount))? This cannot be undone.")
        }
        .alert("Delete \(selectedPayableIds.count) Item\(selectedPayableIds.count == 1 ? "" : "s")", isPresented: $showingBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await performBulkDelete(deleteEntireSeries: false)
                }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedPayableIds.count) payable\(selectedPayableIds.count == 1 ? "" : "s")? This cannot be undone.")
        }
        .confirmationDialog(
            "Some Selected Items Are Recurring",
            isPresented: $showingRecurringDeletePrompt,
            titleVisibility: .visible
        ) {
            Button("Delete Only These \(selectedPayableIds.count) Item\(selectedPayableIds.count == 1 ? "" : "s")", role: .destructive) {
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
            Text("Choose whether to delete only the selected items, or to delete every payable in the same recurring series (past, present, and future).")
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
                Text("No duplicate payables found.")
            } else {
                Text("Found \(duplicateCount) duplicate payable\(duplicateCount == 1 ? "" : "s") across \(duplicateGroupsToClean.count) recurring item\(duplicateGroupsToClean.count == 1 ? "" : "s"). Delete the duplicates? Paid items will be preserved when possible.")
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
            await loadPayables()
        }
    }
    
    // MARK: - List item builder
    // Two completely separate branches so that in normal mode there is NO
    // .onTapGesture on the row — that's important because an outer tap
    // gesture intercepts taps before they reach the inner Button (the "Paid"
    // pill), causing it to silently no-op.
    @ViewBuilder
    private func payableListItem(payable: Payable, showHistory: Bool) -> some View {
        let isSelected = selectedPayableIds.contains(payable.id)
        if isSelectionMode {
            PayableRow(
                payable: payable,
                onDelete: nil,
                onMarkPaid: nil,
                showHistory: showHistory,
                isSelectionMode: true,
                isSelected: isSelected
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .onTapGesture {
                toggleSelection(payable)
            }
        } else {
            PayableRow(
                payable: payable,
                onDelete: nil,
                onMarkPaid: showHistory ? nil : {
                    Task { await markAsPaid(payable) }
                },
                onEdit: { payableToEdit = payable },
                showHistory: showHistory,
                isSelectionMode: false,
                isSelected: false
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    payableToDelete = payable
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
                
                Text("\(selectedPayableIds.count) selected")
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
                        .background(selectedPayableIds.isEmpty ? Color.gray.opacity(0.5) : Color.green)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(selectedPayableIds.isEmpty)
            } else {
                // Delete (left) — enters selection mode
                Button(action: enterSelectionMode) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .disabled(payables.isEmpty)
                .opacity(payables.isEmpty ? 0.4 : 1)
                
                Spacer()
                
                // Add (right)
                Button(action: { showingAddPayable = true }) {
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
            selectedPayableIds = []
        }
    }
    
    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode = false
            selectedPayableIds = []
        }
    }
    
    private func toggleSelection(_ payable: Payable) {
        if selectedPayableIds.contains(payable.id) {
            selectedPayableIds.remove(payable.id)
        } else {
            selectedPayableIds.insert(payable.id)
        }
    }
    
    private var selectedPayables: [Payable] {
        payables.filter { selectedPayableIds.contains($0.id) }
    }
    
    private func countItemsInSelectedRecurringSeries() -> Int {
        let recurringSelected = selectedPayables.filter { $0.frequency != .none }
        let chainKeys = Set(recurringSelected.map { chainKey(for: $0) })
        let nonRecurringSelected = selectedPayables.filter { $0.frequency == .none }
        let chainItems = payables.filter { chainKeys.contains(chainKey(for: $0)) }
        // Combine: every payable in the affected chains, plus any non-recurring
        // items that were selected (those just get deleted as-is).
        return chainItems.count + nonRecurringSelected.count
    }
    
    private func handleBulkDeleteTapped() {
        guard !selectedPayableIds.isEmpty else { return }
        let recurringSelected = selectedPayables.filter { $0.frequency != .none }
        if recurringSelected.isEmpty {
            showingBulkDeleteConfirmation = true
        } else {
            showingRecurringDeletePrompt = true
        }
    }
    
    private func performBulkDelete(deleteEntireSeries: Bool) async {
        var idsToDelete: Set<String> = []
        
        if deleteEntireSeries {
            // For every recurring item selected, expand to the full chain.
            // Non-recurring items are deleted only as themselves.
            let recurringSelected = selectedPayables.filter { $0.frequency != .none }
            let chainKeys = Set(recurringSelected.map { chainKey(for: $0) })
            for payable in payables where chainKeys.contains(chainKey(for: payable)) {
                idsToDelete.insert(payable.id)
            }
            for payable in selectedPayables where payable.frequency == .none {
                idsToDelete.insert(payable.id)
            }
        } else {
            idsToDelete = selectedPayableIds
        }
        
        var errorCount = 0
        for id in idsToDelete {
            do {
                try await FirebaseService.shared.deletePayable(
                    userId: userId,
                    locationId: locationId,
                    payableId: id
                )
            } catch {
                errorCount += 1
                print("Failed to delete payable \(id): \(error.localizedDescription)")
            }
        }
        
        if errorCount > 0 {
            errorMessage = "Failed to delete \(errorCount) item\(errorCount == 1 ? "" : "s")."
        }
        
        exitSelectionMode()
        await loadPayables()
    }
    
    private func loadPayables() async {
        isLoading = true
        errorMessage = nil
        do {
            payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: locationId)
            // Check and create recurring items
            await checkAndCreateRecurringPayables()
            // Reload to get any newly created items
            payables = try await FirebaseService.shared.fetchPayables(userId: userId, locationId: locationId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func deletePayable(_ payable: Payable) async {
        do {
            try await FirebaseService.shared.deletePayable(userId: userId, locationId: locationId, payableId: payable.id)
            await loadPayables()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func markAsPaid(_ payable: Payable) async {
        do {
            let updatedPayable = Payable(
                id: payable.id,
                locationId: payable.locationId,
                payTo: payable.payTo,
                amount: payable.amount,
                dueDate: payable.dueDate,
                createdAt: payable.createdAt,
                notes: payable.notes,
                frequency: payable.frequency,
                isPaid: true,
                paidAt: Date(),
                originalPayableId: payable.originalPayableId
            )
            try await FirebaseService.shared.updatePayable(userId: userId, locationId: locationId, payable: updatedPayable)
            
            // If it's a recurring item, schedule the next occurrence
            if payable.frequency != .none, let dueDate = payable.dueDate {
                await scheduleNextRecurringPayable(payable: payable, dueDate: dueDate)
            }
            
            await loadPayables()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // Identifies the recurring chain a payable belongs to.
    // The very first payable in a chain has no `originalPayableId`, so its own id
    // is the chain key; every child created by the auto-spawn logic copies that id forward.
    private func chainKey(for payable: Payable) -> String {
        payable.originalPayableId ?? payable.id
    }
    
    // Returns true if any payable in the same chain already has a due date
    // within ±1 day of `targetDate` (paid OR unpaid). Used to prevent the
    // auto-spawn logic from creating duplicates.
    private func hasItemInChain(chainKey: String, near targetDate: Date) -> Bool {
        let calendar = Calendar.current
        return payables.contains { p in
            self.chainKey(for: p) == chainKey &&
            abs(calendar.dateComponents([.day], from: p.dueDate ?? Date(), to: targetDate).day ?? 999) <= 1
        }
    }
    
    private func scheduleNextRecurringPayable(payable: Payable, dueDate: Date) async {
        let calendar = Calendar.current
        var nextDueDate: Date?
        
        switch payable.frequency {
        case .weekly:
            nextDueDate = calendar.date(byAdding: .weekOfYear, value: 1, to: dueDate)
        case .monthly:
            nextDueDate = calendar.date(byAdding: .month, value: 1, to: dueDate)
        case .none:
            return
        }
        
        guard let nextDate = nextDueDate else { return }
        
        // Don't create a duplicate if this chain already has an item near this date.
        if hasItemInChain(chainKey: chainKey(for: payable), near: nextDate) { return }
        
        // Create new payable 5 days before the next due date
        let createDate = calendar.date(byAdding: .day, value: -5, to: nextDate) ?? nextDate
        
        // Only create if we're within 5 days before or after the create date
        let now = Date()
        if now >= createDate {
            let newPayable = Payable(
                locationId: locationId,
                payTo: payable.payTo,
                amount: payable.amount,
                dueDate: nextDate,
                notes: payable.notes,
                frequency: payable.frequency,
                originalPayableId: payable.originalPayableId ?? payable.id
            )
            
            do {
                try await FirebaseService.shared.savePayable(userId: userId, locationId: locationId, payable: newPayable)
            } catch {
                print("Error creating next recurring payable: \(error.localizedDescription)")
            }
        }
    }
    
    // Check and create recurring items that should appear 5 days before due date.
    // Only the *latest* paid payable in each chain is used as the seed for the
    // next cycle, otherwise older paid items would each try to spawn duplicates
    // of cycles that have already advanced past them.
    private func checkAndCreateRecurringPayables() async {
        let calendar = Calendar.current
        let now = Date()
        
        // Group paid recurring payables by chain, keeping only the one with the
        // most recent due date per chain.
        let paidRecurring = payables.filter { $0.isPaid && $0.frequency != .none }
        var latestPaidByChain: [String: Payable] = [:]
        for paid in paidRecurring {
            let key = chainKey(for: paid)
            if let existing = latestPaidByChain[key] {
                let existingDue = existing.dueDate ?? .distantPast
                let candidateDue = paid.dueDate ?? .distantPast
                if candidateDue > existingDue {
                    latestPaidByChain[key] = paid
                }
            } else {
                latestPaidByChain[key] = paid
            }
        }
        
        for paidPayable in latestPaidByChain.values {
            guard let originalDueDate = paidPayable.dueDate else { continue }
            
            // Calculate next due date based on frequency
            var nextDueDate: Date?
            switch paidPayable.frequency {
            case .weekly:
                nextDueDate = calendar.date(byAdding: .weekOfYear, value: 1, to: originalDueDate)
            case .monthly:
                nextDueDate = calendar.date(byAdding: .month, value: 1, to: originalDueDate)
            case .none:
                continue
            }
            
            guard let nextDate = nextDueDate else { continue }
            
            // Skip if this chain already has any item (paid or unpaid) at the next date.
            if hasItemInChain(chainKey: chainKey(for: paidPayable), near: nextDate) { continue }
            
            // Check if we should create a new one (5 days before due date)
            let createDate = calendar.date(byAdding: .day, value: -5, to: nextDate) ?? nextDate
            
            if now >= createDate {
                let newPayable = Payable(
                    locationId: locationId,
                    payTo: paidPayable.payTo,
                    amount: paidPayable.amount,
                    dueDate: nextDate,
                    notes: paidPayable.notes,
                    frequency: paidPayable.frequency,
                    originalPayableId: paidPayable.originalPayableId ?? paidPayable.id
                )
                
                do {
                    try await FirebaseService.shared.savePayable(userId: userId, locationId: locationId, payable: newPayable)
                } catch {
                    print("Error creating recurring payable: \(error.localizedDescription)")
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
    
    // Identify duplicate payables — same recurring chain + same due-date day.
    // Returns groups of size > 1; each group's order has paid items first
    // (most recently paid), then unpaid items by createdAt descending. The
    // *first* item in each group is the one to keep; the rest are duplicates.
    private func findDuplicateGroups() -> [[Payable]] {
        let calendar = Calendar.current
        // Key: chain id + due-date day (or "no-date" string)
        var grouped: [String: [Payable]] = [:]
        for payable in payables {
            let chain = chainKey(for: payable)
            let dayKey: String
            if let due = payable.dueDate {
                let day = calendar.startOfDay(for: due)
                dayKey = "\(day.timeIntervalSince1970)"
            } else {
                dayKey = "no-date"
            }
            let key = "\(chain)|\(dayKey)"
            grouped[key, default: []].append(payable)
        }
        
        return grouped.values
            .filter { $0.count > 1 }
            .map { group in
                group.sorted { lhs, rhs in
                    // Paid items take priority (preserved over unpaid duplicates)
                    if lhs.isPaid != rhs.isPaid { return lhs.isPaid && !rhs.isPaid }
                    // Among paid: most recently paid wins
                    if lhs.isPaid && rhs.isPaid {
                        return (lhs.paidAt ?? .distantPast) > (rhs.paidAt ?? .distantPast)
                    }
                    // Among unpaid: most recently created wins
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
        
        // Each group's first item is "the keeper"; everything else is a duplicate.
        for group in duplicateGroupsToClean {
            for duplicate in group.dropFirst() {
                do {
                    try await FirebaseService.shared.deletePayable(
                        userId: userId,
                        locationId: locationId,
                        payableId: duplicate.id
                    )
                    deletedCount += 1
                } catch {
                    errorCount += 1
                    print("Failed to delete duplicate payable \(duplicate.id): \(error.localizedDescription)")
                }
            }
        }
        
        duplicateGroupsToClean = []
        await loadPayables()
        
        if deletedCount == 0 && errorCount == 0 {
            cleanupResultMessage = "No duplicates were removed."
        } else if errorCount > 0 {
            cleanupResultMessage = "Removed \(deletedCount) duplicate\(deletedCount == 1 ? "" : "s"). \(errorCount) failed."
        } else {
            cleanupResultMessage = "Removed \(deletedCount) duplicate payable\(deletedCount == 1 ? "" : "s")."
        }
    }
}

struct PayableRow: View {
    let payable: Payable
    let onDelete: (() -> Void)?
    let onMarkPaid: (() -> Void)?
    var onEdit: (() -> Void)? = nil
    let showHistory: Bool
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    
    // True when this payable has a due date in the past and hasn't been paid yet.
    // Compared at start-of-day so a payable "due today" isn't overdue until tomorrow.
    private var isOverdue: Bool {
        guard let dueDate = payable.dueDate, !payable.isPaid else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: Date())
    }
    
    private var daysLate: Int {
        guard let dueDate = payable.dueDate else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: Date())
        )
        return max(0, components.day ?? 0)
    }
    
    // For history rows: how many days late was the actual payment?
    private var paidLateDays: Int {
        guard let dueDate = payable.dueDate, let paidAt = payable.paidAt else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: paidAt)
        )
        return max(0, components.day ?? 0)
    }
    
    // The "info" half of the row — everything except the Paid pill.
    // Tapping anywhere inside this view triggers Edit when onEdit is set.
    @ViewBuilder
    private var infoContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(payable.payTo)
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
                
                if payable.frequency != .none {
                    Text(payable.frequency.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                if let dueDate = payable.dueDate {
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
                
                if showHistory, let paidAt = payable.paidAt {
                    HStack(spacing: 6) {
                        Text("Paid: \(paidAt, formatter: dateFormatter)")
                            .font(.caption)
                            .foregroundColor(.green)
                        if paidLateDays > 0 {
                            Text("(\(paidLateDays) day\(paidLateDays == 1 ? "" : "s") late)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                if let notes = payable.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                }
            }
            
            Spacer()
            
            Text(formatCurrency(payable.amount))
                .font(.headline)
                .foregroundColor(showHistory ? .green : .red)
        }
        // Force the whole HStack (including the Spacer) to be hit-testable,
        // so taps in the gap also register as Edit instead of falling through.
        .contentShape(Rectangle())
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
                // EDIT TAP TARGET — the info content half.
                // Disabled in selection mode so the outer .onTapGesture
                // (toggle selection) handles the tap instead.
                if let onEdit = onEdit, !isSelectionMode {
                    Button(action: onEdit) {
                        infoContent
                    }
                    .buttonStyle(.plain)
                } else {
                    infoContent
                }
                
                // PAID TAP TARGET — its own sibling button, hit-tested
                // independently from the edit area above.
                if !showHistory && !isSelectionMode {
                    if let onMarkPaid = onMarkPaid {
                        Button(action: onMarkPaid) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                Text("Paid")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            // Give the Paid pill a generous tap area so users
                            // don't accidentally hit the edit area when aiming
                            // at the small circle icon.
                            .padding(.leading, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Theme.cloudWhite)
            .cornerRadius(12)
            .overlay(
                // Red stripe for overdue, blue stripe for selected.
                // Selection takes precedence visually when in selection mode.
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

struct AddPayableView: View {
    let userId: String
    let locationId: String
    // When non-nil, the sheet runs in EDIT mode for this payable.
    // When nil, it's CREATE mode (the original flow).
    let existing: Payable?
    // All other payables already loaded in the parent — used to find sibling
    // items in the same recurring chain when the user picks "this and future".
    let siblings: [Payable]
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var payTo = ""
    @State private var amount = ""
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var selectedDate = Date()
    @State private var notes = ""
    @State private var frequency: RecurringFrequency = .none
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didPrefill = false
    @State private var showingRecurringScopePrompt = false
    
    init(
        userId: String,
        locationId: String,
        existing: Payable? = nil,
        siblings: [Payable] = [],
        onSave: @escaping () -> Void
    ) {
        self.userId = userId
        self.locationId = locationId
        self.existing = existing
        self.siblings = siblings
        self.onSave = onSave
    }
    
    private var isEditing: Bool { existing != nil }
    
    // True only when the user is editing a still-unpaid recurring item that
    // has siblings in its chain. Paid items have already been "spent" — we
    // never propagate edits onto historical records.
    private var canPropagateToFuture: Bool {
        guard let existing = existing else { return false }
        guard existing.frequency != .none, !existing.isPaid else { return false }
        return !futureSiblings.isEmpty
    }
    
    // All OTHER unpaid items in the same chain whose due-date is at or after
    // the edited item's due-date (or all unpaid siblings if no due-date).
    private var futureSiblings: [Payable] {
        guard let existing = existing, existing.frequency != .none else { return [] }
        let key = existing.originalPayableId ?? existing.id
        return siblings.filter { other in
            guard other.id != existing.id else { return false }
            guard !other.isPaid else { return false }
            let otherKey = other.originalPayableId ?? other.id
            guard otherKey == key else { return false }
            if let editedDue = existing.dueDate, let otherDue = other.dueDate {
                return otherDue >= editedDue
            }
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Payable Details") {
                        TextField("Pay To", text: $payTo)
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
            .navigationTitle(isEditing ? "Edit Payable" : "Add Payable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Save") {
                        if isEditing && canPropagateToFuture {
                            showingRecurringScopePrompt = true
                        } else {
                            Task { await savePayable(propagateToFuture: false) }
                        }
                    }
                    .disabled(payTo.isEmpty || amount.isEmpty || isSaving)
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
            .confirmationDialog(
                "This is a Recurring Payable",
                isPresented: $showingRecurringScopePrompt,
                titleVisibility: .visible
            ) {
                Button("Update Just This One") {
                    Task { await savePayable(propagateToFuture: false) }
                }
                Button("Update This & \(futureSiblings.count) Future Item\(futureSiblings.count == 1 ? "" : "s")") {
                    Task { await savePayable(propagateToFuture: true) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Apply your changes to only this entry, or to all future unpaid entries in this recurring series? Past paid entries are never modified.")
            }
            .onAppear { prefillIfNeeded() }
        }
    }
    
    private func prefillIfNeeded() {
        guard !didPrefill, let existing = existing else { return }
        payTo = existing.payTo
        amount = String(format: "%.2f", existing.amount)
        if let due = existing.dueDate {
            hasDueDate = true
            selectedDate = due
        } else {
            hasDueDate = false
        }
        notes = existing.notes ?? ""
        frequency = existing.frequency
        didPrefill = true
    }
    
    private func savePayable(propagateToFuture: Bool) async {
        guard let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }
        
        isSaving = true
        do {
            if let existing = existing {
                // EDIT — preserve id, locationId, createdAt, isPaid/paidAt,
                // originalPayableId so we don't break the recurring chain or
                // wipe out paid status of a historical entry.
                let updated = Payable(
                    id: existing.id,
                    locationId: existing.locationId,
                    payTo: payTo,
                    amount: amountValue,
                    dueDate: hasDueDate ? selectedDate : nil,
                    createdAt: existing.createdAt,
                    notes: notes.isEmpty ? nil : notes,
                    frequency: frequency,
                    isPaid: existing.isPaid,
                    paidAt: existing.paidAt,
                    originalPayableId: existing.originalPayableId
                )
                try await FirebaseService.shared.updatePayable(userId: userId, locationId: locationId, payable: updated)
                
                if propagateToFuture {
                    // Apply payTo / amount / frequency / notes to every future
                    // unpaid sibling. Each sibling keeps its own dueDate and
                    // paid status (none here — futureSiblings filters those).
                    for sibling in futureSiblings {
                        let updatedSibling = Payable(
                            id: sibling.id,
                            locationId: sibling.locationId,
                            payTo: payTo,
                            amount: amountValue,
                            dueDate: sibling.dueDate,
                            createdAt: sibling.createdAt,
                            notes: notes.isEmpty ? nil : notes,
                            frequency: frequency,
                            isPaid: sibling.isPaid,
                            paidAt: sibling.paidAt,
                            originalPayableId: sibling.originalPayableId
                        )
                        try await FirebaseService.shared.updatePayable(userId: userId, locationId: locationId, payable: updatedSibling)
                    }
                }
            } else {
                let payable = Payable(
                    locationId: locationId,
                    payTo: payTo,
                    amount: amountValue,
                    dueDate: hasDueDate ? selectedDate : nil,
                    notes: notes.isEmpty ? nil : notes,
                    frequency: frequency
                )
                try await FirebaseService.shared.savePayable(userId: userId, locationId: locationId, payable: payable)
            }
            dismiss()
            onSave()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

