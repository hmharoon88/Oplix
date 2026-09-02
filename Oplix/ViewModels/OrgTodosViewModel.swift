//
//  OrgTodosViewModel.swift
//  Oplix
//
//  Live org-level to-dos for manager Home. Uses the same Firestore path
//  as the web manager dashboard so edits sync both ways.
//

import Foundation

@MainActor
final class OrgTodosViewModel: ObservableObject {
    @Published private(set) var todos: [OrgTodo] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let userId: String
    private let firebaseService = FirebaseService.shared

    var sortedTodos: [OrgTodo] { OrgTodo.sorted(todos) }
    var openTodos: [OrgTodo] { sortedTodos.filter { !$0.isCompleted } }
    var completedTodos: [OrgTodo] { sortedTodos.filter { $0.isCompleted } }
    var openCount: Int { OrgTodo.openCount(todos) }

    init(userId: String) {
        self.userId = userId
        startObserving()
    }

    deinit {
        let uid = userId
        Task { @MainActor in
            FirebaseService.shared.removeOrgTodosListener(userId: uid)
        }
    }

    func startObserving() {
        isLoading = todos.isEmpty
        firebaseService.observeOrgTodos(userId: userId) { [weak self] items in
            Task { @MainActor in
                self?.todos = items
                self?.isLoading = false
            }
        }
    }

    func add(title: String, dueDate: String = "") async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let todo = OrgTodo(title: trimmed, dueDate: dueDate)
        do {
            try await firebaseService.saveOrgTodo(userId: userId, todo: todo, isNew: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ todo: OrgTodo, resetDueReminderSent: Bool = false) async {
        do {
            try await firebaseService.saveOrgTodo(
                userId: userId,
                todo: todo,
                isNew: false,
                resetDueReminderSent: resetDueReminderSent
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleComplete(_ todo: OrgTodo) async {
        var updated = todo
        updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? Date() : nil
        await update(updated)
    }

    func delete(_ todo: OrgTodo) async {
        do {
            try await firebaseService.deleteOrgTodo(userId: userId, todoId: todo.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
