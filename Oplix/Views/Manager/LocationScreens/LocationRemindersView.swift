//
//  LocationRemindersView.swift
//  Oplix
//
//  Per-location reminders for the manager account.
//

import SwiftUI

struct LocationRemindersView: View {
    let userId: String
    let locationId: String
    /// Called after add / toggle / delete so the location grid badge can refresh.
    var onChanged: () -> Void = {}

    @State private var reminders: [LocationReminder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var reminderToEdit: LocationReminder?

    private var sortedReminders: [LocationReminder] {
        reminders.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted && b.isCompleted }
            let ad = a.dueDate ?? .distantFuture
            let bd = b.dueDate ?? .distantFuture
            if ad != bd { return ad < bd }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()

            if isLoading && reminders.isEmpty {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.cloudBlue)
            } else {
                List {
                    if sortedReminders.isEmpty {
                        Text("No reminders yet. Tap + to add one for this location.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sortedReminders) { reminder in
                            reminderRow(reminder)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.cloudWhite.opacity(0.95))
                                        .padding(.vertical, 4)
                                )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    reminderToEdit = nil
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Add reminder")
            }
        }
        .sheet(isPresented: $showingAdd) {
            LocationReminderEditSheet(
                userId: userId,
                locationId: locationId,
                existing: reminderToEdit,
                onSave: {
                    Task { await reload() }
                    onChanged()
                },
                onDismiss: {
                    showingAdd = false
                    reminderToEdit = nil
                }
            )
            .id(reminderToEdit?.id ?? "new")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private func reminderRow(_ reminder: LocationReminder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await toggleCompleted(reminder) }
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.title)
                    .font(.headline)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)

                if let due = reminder.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                reminderToEdit = reminder
                showingAdd = true
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await deleteReminder(reminder) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func reload() async {
        if reminders.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            reminders = try await FirebaseService.shared.fetchLocationReminders(userId: userId, locationId: locationId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleCompleted(_ reminder: LocationReminder) async {
        var updated = reminder
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? Date() : nil
        do {
            try await FirebaseService.shared.saveLocationReminder(userId: userId, locationId: locationId, reminder: updated)
            if let i = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[i] = updated
            }
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteReminder(_ reminder: LocationReminder) async {
        do {
            try await FirebaseService.shared.deleteLocationReminder(userId: userId, locationId: locationId, reminderId: reminder.id)
            reminders.removeAll { $0.id == reminder.id }
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add / edit sheet

private struct LocationReminderEditSheet: View {
    let userId: String
    let locationId: String
    let existing: LocationReminder?
    var onSave: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var titleText = ""
    @State private var notesText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $titleText)
                    TextField("Notes (optional)", text: $notesText, axis: .vertical)
                        .lineLimit(3 ... 6)
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle(existing == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let e = existing {
                    titleText = e.title
                    notesText = e.notes ?? ""
                    if let d = e.dueDate {
                        hasDueDate = true
                        dueDate = d
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminder: LocationReminder
        if let e = existing {
            reminder = LocationReminder(
                id: e.id,
                locationId: locationId,
                title: trimmed,
                notes: notes.isEmpty ? nil : notes,
                dueDate: hasDueDate ? dueDate : nil,
                createdAt: e.createdAt,
                isCompleted: e.isCompleted,
                completedAt: e.completedAt
            )
        } else {
            reminder = LocationReminder(
                locationId: locationId,
                title: trimmed,
                notes: notes.isEmpty ? nil : notes,
                dueDate: hasDueDate ? dueDate : nil
            )
        }
        do {
            try await FirebaseService.shared.saveLocationReminder(userId: userId, locationId: locationId, reminder: reminder)
            onSave()
            onDismiss()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
