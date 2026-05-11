//
//  ManagerDashboardViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class ManagerDashboardViewModel: ObservableObject {
    @Published var locations: [Location] = []
    // Manager-wide tasks, grouped by locationId for fast row-time score lookup.
    @Published var tasksByLocation: [String: [WorkTask]] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    var userId: String? // Set by the view that uses this ViewModel
    
    func loadLocations() async {
        guard let userId = userId else {
            errorMessage = "User ID not set"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let locationsTask = firebaseService.fetchLocations(userId: userId)
            async let tasksTask = firebaseService.fetchManagerTasks(userId: userId)

            locations = try await locationsTask
            // Tasks are non-critical — silently fall back to empty so location
            // rows still render without the score bar if anything goes wrong.
            do {
                let tasks = try await tasksTask
                // Skip manager-level tasks (locationId == nil) — only group
                // tasks that belong to a specific location, since the score
                // bar is rendered per-location.
                tasksByLocation = Dictionary(
                    grouping: tasks.compactMap { task -> (String, WorkTask)? in
                        guard let locationId = task.locationId else { return nil }
                        return (locationId, task)
                    },
                    by: { $0.0 }
                ).mapValues { pairs in pairs.map { $0.1 } }
            } catch {
                tasksByLocation = [:]
            }
        } catch {
            errorMessage = "Failed to load locations: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // Score helpers consumed by LocationRow. Returning `nil` when there are
    // no tasks at the location keeps the row in its "no progress bar" state
    // (clean look on freshly-created locations).
    func todayScore(for location: Location) -> LocationScoreSegment? {
        let tasks = tasksByLocation[location.id] ?? []
        return TaskProgress.locationToday(tasks: tasks)
    }

    func sevenDayScore(for location: Location) -> LocationScoreSegment? {
        let tasks = tasksByLocation[location.id] ?? []
        return TaskProgress.locationSevenDay(tasks: tasks)
    }
    
    func deleteLocation(_ location: Location) async {
        guard let userId = userId else {
            errorMessage = "User ID not set"
            return
        }
        do {
            try await firebaseService.deleteLocation(userId: userId, locationId: location.id)
            await loadLocations()
        } catch {
            errorMessage = "Failed to delete location: \(error.localizedDescription)"
        }
    }
    
    func startObservingLocations() {
        guard let userId = userId else { return }
        let locationsCompletion: ([Location]) -> Void = { [weak self] locations in
            guard let self = self else { return }
            self.locations = locations
        }
        firebaseService.observeLocations(userId: userId, completion: locationsCompletion)

        // Live-update the score bars whenever any task changes (completions,
        // edits, adds, deletes anywhere in the manager's locations).
        let tasksCompletion: ([WorkTask]) -> Void = { [weak self] tasks in
            guard let self = self else { return }
            // Cross-reference the manager-level mirror with each location's
            // actual tasks subcollection. Any manager-level task whose
            // location either:
            //   (a) doesn't have it in `Location.tasks`, OR
            //   (b) doesn't return it from `fetchTasks`,
            // is treated as an orphan (typically left behind by an older
            // delete that didn't mirror) and pruned from both Firestore and
            // the local map. This keeps the score honest after past deletes
            // and prevents the bar from "remembering" deleted tasks.
            Task { [weak self] in
                guard let self = self else { return }
                let pruned = await self.pruneOrphans(tasks: tasks, userId: userId)
                self.tasksByLocation = Dictionary(
                    grouping: pruned.compactMap { task -> (String, WorkTask)? in
                        guard let locationId = task.locationId else { return nil }
                        return (locationId, task)
                    },
                    by: { $0.0 }
                ).mapValues { pairs in pairs.map { $0.1 } }
            }
        }
        firebaseService.observeManagerTasks(userId: userId, completion: tasksCompletion)
    }

    // Drops manager-level tasks that no longer exist at their per-location
    // collection — i.e. orphans left over from older deletes that didn't
    // mirror. Also fires a best-effort `deleteManagerTask` so we don't have
    // to re-prune them every time.
    private func pruneOrphans(tasks: [WorkTask], userId: String) async -> [WorkTask] {
        var live: [WorkTask] = []
        // Group by location so we only fetch each location's tasks once.
        let byLocation = Dictionary(grouping: tasks.compactMap { task -> (String, WorkTask)? in
            guard let locationId = task.locationId else { return nil }
            return (locationId, task)
        }, by: { $0.0 })
            .mapValues { pairs in pairs.map { $0.1 } }

        for (locationId, locationTasks) in byLocation {
            do {
                let actual = try await firebaseService.fetchTasks(userId: userId, locationId: locationId)
                let actualIds = Set(actual.map { $0.id })
                for task in locationTasks {
                    if actualIds.contains(task.id) {
                        live.append(task)
                    } else {
                        // Best-effort prune of the orphan — don't block on failure.
                        Task {
                            try? await firebaseService.deleteManagerTask(userId: userId, taskId: task.id)
                        }
                    }
                }
            } catch {
                // If the per-location fetch fails (e.g. transient), assume
                // the manager-level state is fine and pass tasks through
                // untouched rather than wiping the bar.
                live.append(contentsOf: locationTasks)
            }
        }

        return live
    }
}

