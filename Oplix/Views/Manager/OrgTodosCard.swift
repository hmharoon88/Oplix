//
//  OrgTodosCard.swift
//  Oplix
//
//  Manager Home "To-Do" card — org-wide checklist synced with the web app
//  via users/{uid}/orgTodos.
//

import SwiftUI

struct OrgTodosCard: View {
    @ObservedObject var viewModel: OrgTodosViewModel

    @State private var newTitle = ""
    @State private var newHasDueDate = false
    @State private var newDueDate = Date()
    @State private var todoToEdit: OrgTodo?
    @State private var showingEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if viewModel.isLoading && viewModel.todos.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.todos.isEmpty {
                emptyState
            } else {
                todoList
            }

            addRow
        }
        .oplixCard()
        .sheet(isPresented: $showingEdit) {
            OrgTodoEditSheet(
                existing: todoToEdit,
                onSave: { updated, resetSent in
                    Task { await viewModel.update(updated, resetDueReminderSent: resetSent) }
                },
                onDismiss: {
                    showingEdit = false
                    todoToEdit = nil
                }
            )
            .id(todoToEdit?.id ?? "new")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.cloudBlue)
            Text("To-Do")
                .font(.headline)
                .foregroundColor(.black)
            if viewModel.openCount > 0 {
                Text("\(viewModel.openCount)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.cloudBlue))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing on your list")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                Text("Add items you need to handle — org-wide, not tied to a facility")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var todoList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.openTodos.enumerated()), id: \.element.id) { idx, todo in
                todoRow(todo)
                if idx < viewModel.openTodos.count - 1 || !viewModel.completedTodos.isEmpty {
                    Divider().padding(.leading, 52)
                }
            }

            if !viewModel.completedTodos.isEmpty {
                Text("Completed (\(viewModel.completedTodos.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                ForEach(Array(viewModel.completedTodos.enumerated()), id: \.element.id) { idx, todo in
                    todoRow(todo)
                    if idx < viewModel.completedTodos.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func todoRow(_ todo: OrgTodo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await viewModel.toggleComplete(todo) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        todo.isCompleted ? Color.green :
                        todo.isOverdue ? Color.red : Color.secondary
                    )
            }
            .buttonStyle(.plain)

            Button {
                todoToEdit = todo
                showingEdit = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(todo.isCompleted ? .secondary : .primary)
                        .strikethrough(todo.isCompleted)
                        .multilineTextAlignment(.leading)

                    if let formatted = todo.formattedDueDate {
                        HStack(spacing: 0) {
                            Text(formatted)
                            if !todo.dueHint.isEmpty {
                                Text(" · \(todo.dueHint)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(todo.isOverdue && !todo.isCompleted ? .red : .secondary)
                    } else if !todo.dueHint.isEmpty {
                        Text(todo.dueHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !todo.notes.isEmpty {
                        Text(todo.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.delete(todo) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var addRow: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                TextField("Add something to do…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { Task { await submitAdd() } }

                if newHasDueDate {
                    DatePicker("", selection: $newDueDate, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                Button("Add") {
                    Task { await submitAdd() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.cloudBlue)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Toggle("Due date", isOn: $newHasDueDate)
                .font(.caption)
                .tint(Theme.cloudBlue)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func submitAdd() async {
        let due = newHasDueDate ? Self.isoDateString(from: newDueDate) : ""
        await viewModel.add(title: newTitle, dueDate: due)
        newTitle = ""
        newHasDueDate = false
    }

    private static func isoDateString(from date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        return df.string(from: date)
    }
}

// MARK: - Edit sheet

private struct OrgTodoEditSheet: View {
    let existing: OrgTodo?
    var onSave: (OrgTodo, Bool) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var titleText = ""
    @State private var notesText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var dueReminder = DueDateReminder()

    var body: some View {
        NavigationStack {
            Form {
                Section("To-Do") {
                    TextField("Title", text: $titleText)
                    TextField("Notes (optional)", text: $notesText, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date])
                        DueDateReminderFormSection(reminder: $dueReminder)
                    }
                }
            }
            .navigationTitle("Edit to-do")
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
                        save()
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                titleText = e.title
                notesText = e.notes
                if !e.dueDate.isEmpty {
                    hasDueDate = true
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    df.timeZone = TimeZone.current
                    dueDate = df.date(from: e.dueDate) ?? Date()
                }
                dueReminder = DueDateReminder.normalized(e.dueReminder)
            }
        }
    }

    private func save() {
        guard var todo = existing else { return }
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todo.title = trimmed
        todo.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDue = todo.dueDate
        let oldReminder = todo.dueReminder
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        let parsedOldDue = oldDue.isEmpty ? nil : df.date(from: oldDue)
        if hasDueDate {
            todo.dueDate = df.string(from: dueDate)
            todo.dueReminder = DueDateReminder.normalized(dueReminder)
        } else {
            todo.dueDate = ""
            todo.dueReminder = nil
        }
        let newDueValue: Date? = hasDueDate ? dueDate : nil
        let shouldResetSent = DueDateReminder.shouldClearSentFlag(
            oldDue: parsedOldDue,
            newDue: newDueValue,
            oldReminder: oldReminder,
            newReminder: todo.dueReminder
        )
        if shouldResetSent {
            todo.dueReminderSentOn = nil
        }
        onSave(todo, shouldResetSent)
        onDismiss()
        dismiss()
    }
}
