//
//  ManagerTasksViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class ManagerTasksViewModel: ObservableObject {
    @Published var tasks: [WorkTask] = []
    @Published var locations: [Location] = []
    @Published var employees: [Employee] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let tasksTask = firebaseService.fetchManagerTasks(userId: userId)
            async let locationsTask = firebaseService.fetchLocations(userId: userId)
            async let employeesTask = firebaseService.fetchManagerEmployees(userId: userId)
            
            tasks = try await tasksTask
            locations = try await locationsTask
            employees = try await employeesTask
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func createTask(description: String, assignedLocationIds: [String] = [], assignedEmployeeIds: [String] = []) async {
        do {
            let task = WorkTask(
                id: UUID().uuidString,
                description: description,
                assignedEmployeeIds: assignedEmployeeIds,
                locationId: assignedLocationIds.first,
                assignedLocationIds: assignedLocationIds
            )
            
            try await firebaseService.createManagerTask(userId: userId, task: task)
            
            // Assign to locations if any
            for locationId in assignedLocationIds {
                try await firebaseService.assignTaskToLocation(userId: userId, taskId: task.id, locationId: locationId)
            }
            
            await loadData()
        } catch {
            errorMessage = "Failed to create task: \(error.localizedDescription)"
        }
    }
    
    func deleteTask(_ task: WorkTask) async {
        do {
            // Unassign from all locations first
            for locationId in task.assignedLocationIds {
                try? await firebaseService.unassignTaskFromLocation(userId: userId, taskId: task.id, locationId: locationId)
            }
            
            // Delete from manager collection
            try await firebaseService.deleteManagerTask(userId: userId, taskId: task.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
        }
    }
    
    func assignTaskToLocation(taskId: String, locationId: String) async {
        do {
            try await firebaseService.assignTaskToLocation(userId: userId, taskId: taskId, locationId: locationId)
            await loadData()
        } catch {
            errorMessage = "Failed to assign task: \(error.localizedDescription)"
        }
    }
    
    func unassignTaskFromLocation(taskId: String, locationId: String) async {
        do {
            try await firebaseService.unassignTaskFromLocation(userId: userId, taskId: taskId, locationId: locationId)
            await loadData()
        } catch {
            errorMessage = "Failed to unassign task: \(error.localizedDescription)"
        }
    }
}

