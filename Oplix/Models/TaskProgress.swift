//
//  TaskProgress.swift
//  Oplix
//
//  Created on 5/10/26.
//

import Foundation

// Lightweight, pure helpers for computing per-employee and per-location task
// completion stats used by Employee/Location row badges and progress bars.
//
// All maths here are cycle-aware (daily/weekly/monthly/one-time) and run
// purely off in-memory `[WorkTask]` arrays — callers fetch the tasks once
// (e.g. via FirebaseService.fetchManagerTasks) and feed them in.
enum TaskProgress {

    // MARK: - Employee progress (current cycle, "today" view)

    // For one specific employee, given a set of tasks, returns:
    //   completed: number of tasks they finished in the current cycle
    //   assigned : number of tasks currently assigned to them
    //
    // Recurring frequency is honoured by `WorkTask.isCompletedBy(_:)`, so a
    // daily task completed yesterday won't be counted as completed today.
    static func employeeToday(
        tasks: [WorkTask],
        employeeId: String
    ) -> (completed: Int, assigned: Int) {
        let assignedTasks = tasks.filter { $0.assignedEmployeeIds.contains(employeeId) }
        let completed = assignedTasks.filter { $0.isCompletedBy(employeeId: employeeId) }.count
        return (completed, assignedTasks.count)
    }

    // MARK: - Location score (today + 7-day rolling)

    // "Today" score for a location: the share of tasks at that location that
    // are fully done in their current cycle.
    //
    // A task is "fully done" when it has at least one assignee AND every
    // currently-assigned employee has completed it in the current cycle.
    // Unassigned tasks are excluded from BOTH numerator and denominator
    // (no one is accountable, so they shouldn't punish the score), and if
    // every task is unassigned we return nil so the row hides the bar
    // entirely — matching the "no tasks at all" empty state.
    static func locationToday(tasks: [WorkTask]) -> LocationScoreSegment? {
        let assignedTasks = tasks.filter { !$0.assignedEmployeeIds.isEmpty }
        guard !assignedTasks.isEmpty else { return nil }
        let done = assignedTasks.filter { task in
            task.assignedEmployeeIds.allSatisfy { task.isCompletedBy(employeeId: $0) }
        }.count
        return LocationScoreSegment(numerator: done, denominator: assignedTasks.count)
    }

    // "Past week" score: ratio of (assignee × cycle) completions actually
    // submitted across the previous 7 *complete* calendar days (yesterday →
    // 7 days ago) vs how many should have been submitted.
    //
    // We deliberately exclude today from this window — today is its own
    // "TODAY" track, and pulling today into the past-week math just dilutes
    // both sides and confuses the user when the cycle is still in progress.
    //
    // "Expected" cycles per task type within the window:
    //   - daily   → number of full days the task has been alive in the window (max 7)
    //   - weekly  → 1 if the task existed for any part of the window, else 0
    //   - monthly → 1 if the task existed for any part of the window, else 0
    //   - oneTime → 1 if the task existed before the window ended, else 0
    //
    // "Alive" is determined by `task.createdAt`. Legacy tasks with no
    // `createdAt` are assumed to have always existed (full 7-day expectation),
    // matching the pre-`createdAt` behaviour for old data.
    //
    // "Actual" is the count of `employeeCompletions` whose timestamp falls
    // inside the window. We don't filter by current assignment so historical
    // assignees who completed before being un-assigned still count toward
    // history (matching the user's intent: "history of tasks completed").
    static func locationSevenDay(
        tasks: [WorkTask],
        now: Date = Date()
    ) -> LocationScoreSegment? {
        // Same accountability rule as locationToday — only assigned tasks
        // count toward "expected", and a location with zero assigned tasks
        // gets no bar at all.
        let assignedTasks = tasks.filter { !$0.assignedEmployeeIds.isEmpty }
        guard !assignedTasks.isEmpty else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        // Window: [todayStart - 7 days, todayStart) — i.e. the previous 7
        // full calendar days, today excluded.
        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: todayStart) else {
            return nil
        }
        let windowEnd = todayStart // exclusive — today belongs to the TODAY track

        var actual = 0
        var expected = 0

        for task in assignedTasks {
            let assigneeCount = task.assignedEmployeeIds.count

            // Effective start of the task's life within the window.
            // Legacy tasks (createdAt == nil) get the full window.
            let effectiveStart: Date = {
                guard let created = task.createdAt else { return windowStart }
                return max(calendar.startOfDay(for: created), windowStart)
            }()
            // If the task was created today (or later), it gets no past-week
            // expectation at all — its first scoring day is today.
            guard effectiveStart < windowEnd else { continue }

            let daysAlive = calendar.dateComponents([.day], from: effectiveStart, to: windowEnd).day ?? 0
            let cyclesInWindow: Int
            switch task.frequency {
            case .daily:
                cyclesInWindow = max(0, min(7, daysAlive))
            case .weekly:
                cyclesInWindow = daysAlive > 0 ? 1 : 0
            case .monthly:
                cyclesInWindow = daysAlive > 0 ? 1 : 0
            case .oneTime:
                cyclesInWindow = daysAlive > 0 ? 1 : 0
            }

            expected += cyclesInWindow * assigneeCount

            for completion in task.employeeCompletions.values
                where completion.timestamp >= windowStart
                    && completion.timestamp < windowEnd
                    && completion.countsAsCompleted {
                actual += 1
            }
        }

        // No expectations across all tasks (everything is brand-new today, or
        // legacy data that doesn't apply) → hide the bar instead of showing a
        // misleading 0%/100%.
        guard expected > 0 else { return nil }

        return LocationScoreSegment(numerator: actual, denominator: expected)
    }
}

// One score segment (today or 7-day) — small helper so views don't have to
// juggle two raw doubles + counts. `percentage` is clamped 0...1.
struct LocationScoreSegment {
    let numerator: Int
    let denominator: Int

    var percentage: Double {
        guard denominator > 0 else { return 0 }
        let p = Double(numerator) / Double(denominator)
        return min(max(p, 0), 1)
    }

    var displayPercent: Int {
        Int((percentage * 100).rounded())
    }
}
