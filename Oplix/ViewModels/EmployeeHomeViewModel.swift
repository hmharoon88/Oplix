//
//  EmployeeHomeViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation
import FirebaseFirestore

@MainActor
class EmployeeHomeViewModel: ObservableObject {
    @Published var employee: Employee?
    @Published var location: Location?
    @Published var tasks: [WorkTask] = []
    @Published var allTasks: [WorkTask] = [] // All tasks at location (for management)
    @Published var allEmployees: [Employee] = [] // All employees at location (for management)
    @Published var currentShift: Shift?
    @Published var allShifts: [Shift] = [] // Store all shifts for stats calculation
    @Published var lastLocationRegisterClose: Shift? // Last closed register for this location
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lotteryTemplate: LotteryFormTemplate?
    /// Last 3 lottery shifts submitted at this location, newest first
    /// (counted across every terminal). Powers the "Recent Lottery" card
    /// on the employee/supervisor home so they can see the over/short of
    /// the most recent shifts even before the day's first submission.
    @Published var recentLotteryForms: [LotteryForm] = []

    /// Announcements addressed to this user, newest first. Powers the
    /// home-screen announcements card + the inbox screen. Already
    /// filtered to `recipientIds.contains(employeeId)` server- and
    /// client-side so the employee only sees what was sent to them.
    @Published var myAnnouncements: [Announcement] = []
    private var announcementsListener: ListenerRegistration?
    
    private let firebaseService = FirebaseService.shared
    let employeeId: String
    let locationId: String
    var managerUserId: String? // Will be set after fetching employee
    private var isLoadDataInProgress = false // Prevent concurrent loadData calls
    private var hasLoadedData = false // Track if data has been successfully loaded
    
    // Computed properties for weekly stats
    var thisWeekHours: Double {
        let calendar = Calendar.current
        let now = Date()
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        return allShifts
            .filter { shift in
                guard let clockOutTime = shift.clockOutTime else { return false }
                let week = calendar.component(.weekOfYear, from: clockOutTime)
                let year = calendar.component(.year, from: clockOutTime)
                return week == currentWeek && year == currentYear && shift.employeeId == employeeId
            }
            .compactMap { $0.hoursWorked }
            .reduce(0, +)
    }
    
    var thisWeekPay: Double {
        guard let hourlyRate = employee?.hourlyRate, hourlyRate > 0 else { return 0.0 }
        return thisWeekHours * hourlyRate
    }

    // MARK: - Task scores (home-screen performance card)

    /// How many of *this* employee's tasks are done in the current cycle vs
    /// how many are assigned to them. Mirrors `TaskProgress.employeeToday` so
    /// the supervisor/team-member home screen and the manager-side employee
    /// row show the same number.
    var myTodayScore: (completed: Int, assigned: Int) {
        TaskProgress.employeeToday(tasks: tasks, employeeId: employeeId)
    }

    /// Recurring tasks missed on past days (read-only on the Tasks tab).
    var missedRecurringItems: [TaskAssignmentAudit.EmployeeMissedRecurringItem] {
        TaskAssignmentAudit.missedRecurringItems(for: employeeId, from: tasks)
    }

    /// Tasks shown in the actionable list: all recurring + corrective until done.
    var actionableTasks: [WorkTask] {
        tasks.filter { task in
            if task.frequency == .oneTime {
                return !task.isCompletedBy(employeeId: employeeId)
            }
            return task.frequency.isRecurring
        }
        .sorted { lhs, rhs in
            let lhsCorrective = lhs.frequency == .oneTime
            let rhsCorrective = rhs.frequency == .oneTime
            if lhsCorrective != rhsCorrective { return lhsCorrective }
            let lhsDone = lhs.isCompletedBy(employeeId: employeeId)
            let rhsDone = rhs.isCompletedBy(employeeId: employeeId)
            if lhsDone != rhsDone { return !lhsDone }
            return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
        }
    }

    /// Location-wide "today" score (% of assigned tasks fully done in the
    /// current cycle). nil when there are no assigned tasks at the location.
    var locationTodayScore: LocationScoreSegment? {
        TaskProgress.locationToday(tasks: allTasks)
    }

    /// Location-wide "past week" score (previous 7 complete days). nil when
    /// there's nothing meaningful to show yet (e.g. brand-new location).
    var locationPastWeekScore: LocationScoreSegment? {
        TaskProgress.locationSevenDay(tasks: allTasks)
    }
    
    init(employeeId: String, locationId: String) {
        self.employeeId = employeeId
        self.locationId = locationId
    }
    
    func loadData() async {
        // Prevent concurrent calls
        guard !isLoadDataInProgress else {
            print("⚠️ EmployeeHomeViewModel.loadData already in progress, skipping...")
            return
        }
        
        // If data has already been loaded, don't reload
        if hasLoadedData && employee != nil && location != nil {
            print("⚠️ EmployeeHomeViewModel.loadData skipped - data already loaded")
            return
        }
        
        isLoadDataInProgress = true
        isLoading = true
        errorMessage = nil
        do {
            // First fetch user to get managerUserId
            let user = try await firebaseService.fetchUser(userId: employeeId)
            guard let managerUserId = user.managerUserId else {
                errorMessage = "Manager user ID not found"
                isLoading = false
                isLoadDataInProgress = false
                return
            }
            self.managerUserId = managerUserId
            
            // Now fetch employee, location, and other data
            async let employeeTask = firebaseService.fetchEmployee(userId: managerUserId, locationId: locationId, employeeId: employeeId)
            async let locationTask = firebaseService.fetchLocation(userId: managerUserId, locationId: locationId)
            async let tasksTask = firebaseService.fetchTasks(userId: managerUserId, locationId: locationId)
            async let shiftsTask = firebaseService.fetchShifts(userId: managerUserId, locationId: locationId)
            async let employeesTask = firebaseService.fetchEmployees(userId: managerUserId, locationId: locationId)
            // Fetch in parallel; we'll filter to today client-side. Failure
            // here is non-fatal — the home screen still works without
            // lottery data, just minus the Lottery Today card.
            async let lotteryFormsTask = firebaseService.fetchLotteryForms(userId: managerUserId, locationId: locationId)
            
            employee = try await employeeTask
            location = try await locationTask
            let fetchedTasks = try await tasksTask
            // Keep both views in sync: `tasks` is what the employee personally
            // owes today (used in the tasks tab), `allTasks` is the full
            // location set used by the home-screen performance card.
            allTasks = fetchedTasks
            tasks = fetchedTasks.filter { $0.isAssignedTo(employeeId: employeeId) }
            let shifts = try await shiftsTask
            // Store all shifts for this employee
            allShifts = shifts.filter { $0.employeeId == employeeId }
            // Show assigned shift (not started) or active shift (clocked in but not out)
            currentShift = allShifts.first { $0.isAssigned || $0.isActive }
            
            // Store all employees for getting names
            allEmployees = try await employeesTask
            
            // Take the 3 most recent lottery submissions across every
            // terminal at this location for the home-screen card.
            // Tolerate fetch failures — lottery data is optional on home.
            do {
                let allForms = try await lotteryFormsTask
                recentLotteryForms = allForms
                    .sorted { $0.submittedAt > $1.submittedAt }
                    .prefix(3)
                    .map { $0 }
                print("🎟️ Recent lottery: fetched \(allForms.count) forms for location \(locationId), kept \(recentLotteryForms.count) most recent.")
            } catch {
                print("⚠️ Recent lottery: fetch failed for location \(locationId): \(error.localizedDescription)")
                recentLotteryForms = []
            }
            
            // Find the last closed register for this location (from any employee)
            await loadLastLocationRegisterClose(managerUserId: managerUserId, locationId: locationId)
            
            // Check for shifts that need auto clock out
            await checkAndAutoClockOut()
            
            hasLoadedData = true // Mark data as loaded
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
        isLoadDataInProgress = false
    }
    
    func clockIn() async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        guard let employee = employee else {
            errorMessage = "Employee data not loaded"
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Check if 24/7 is enabled - if so, allow clocking in at any time
        let scheduledStartToday: Date
        let scheduledEndToday: Date
        let spansMidnight: Bool
        
        if employee.is24Hours == true {
            // For 24/7 employees, set scheduled times to allow clocking in at any time
            // Use current time as start, and 24 hours later as end (no restrictions)
            scheduledStartToday = now
            scheduledEndToday = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            spansMidnight = false
        } else {
            // Get working hours for today (from weekly schedule or fallback to old workingHoursStart/End)
            guard let workingHours = employee.workingHours(for: Date()) else {
                errorMessage = "Working hours not set. Please contact your manager."
                return
            }
            
            let startTimeStr = workingHours.start
            let endTimeStr = workingHours.end
            
            // Parse working hours
            guard let scheduledStart = parseTimeString(startTimeStr),
                  let scheduledEnd = parseTimeString(endTimeStr) else {
                errorMessage = "Invalid working hours format"
                return
            }
            
            // Calculate scheduled times for today
            scheduledStartToday = calendar.date(bySettingHour: calendar.component(.hour, from: scheduledStart),
                                                     minute: calendar.component(.minute, from: scheduledStart),
                                                     second: 0,
                                                     of: today) ?? today
            
            // Calculate end time - check if it's on the same day or next day
            let endHour = calendar.component(.hour, from: scheduledEnd)
            let endMinute = calendar.component(.minute, from: scheduledEnd)
            let scheduledEndSameDay = calendar.date(bySettingHour: endHour,
                                                    minute: endMinute,
                                                    second: 0,
                                                    of: today) ?? today
            
            // Determine if shift spans midnight (end time is earlier than start time on same day)
            if scheduledEndSameDay <= scheduledStartToday {
                // End time is on next day (shift spans midnight)
                scheduledEndToday = calendar.date(byAdding: .day, value: 1, to: scheduledEndSameDay) ?? scheduledEndSameDay
                spansMidnight = true
            } else {
                // End time is on same day (normal shift)
                scheduledEndToday = scheduledEndSameDay
                spansMidnight = false
            }
            
            // Check if current time is within scheduled hours
            let isWithinHours: Bool
            if spansMidnight {
                // Shift spans midnight: allow if now >= start OR now < end (next day)
                isWithinHours = now >= scheduledStartToday || now < scheduledEndToday
            } else {
                // Normal shift: allow if now >= start AND now <= end
                isWithinHours = now >= scheduledStartToday && now <= scheduledEndToday
            }
            
            if !isWithinHours {
                errorMessage = "Clock in is only allowed during scheduled hours (\(startTimeStr) - \(endTimeStr))"
                return
            }
        }
        
        // Check if employee already has an active shift (must clock out first before starting a new one)
        let todayShifts = allShifts.filter { shift in
            guard let clockInTime = shift.clockInTime else { return false }
            return clockInTime >= today && clockInTime < calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        
        // Check if there's already an active shift
        if todayShifts.contains(where: { $0.isActive }) {
            errorMessage = "You are already clocked in. Please clock out first."
            return
        }
        
        // Check if starting late (only for non-24/7 employees)
        let startedLate = employee.is24Hours != true && now > scheduledStartToday
        
        do {
            // Check if there's an assigned shift to start, or create a new one
            if let assignedShift = currentShift, assignedShift.isAssigned {
                // Start the assigned shift
                var updatedShift = assignedShift
                updatedShift.clockInTime = now
                updatedShift.scheduledStartTime = scheduledStartToday
                updatedShift.scheduledEndTime = scheduledEndToday
                updatedShift.startedLate = startedLate
                updatedShift.manuallyClockedOut = true
                try await firebaseService.updateShift(userId: managerUserId, locationId: locationId, shift: updatedShift)
                
                var updatedEmployee = employee
                updatedEmployee.currentShiftStatus = .clockedIn
                try await firebaseService.updateEmployee(userId: managerUserId, locationId: locationId, employee: updatedEmployee)
                
                currentShift = updatedShift
                self.employee = updatedEmployee
            } else {
                // Create a new shift (employee-initiated)
                let shift = Shift(
                    id: UUID().uuidString,
                    employeeId: employeeId,
                    locationId: locationId,
                    clockInTime: now,
                    clockOutTime: nil,
                    assignedAt: nil, // Employee-initiated shifts are not "assigned"
                    acknowledged: false,
                    scheduledStartTime: scheduledStartToday,
                    scheduledEndTime: scheduledEndToday,
                    isAutoClockedOut: false,
                    startedLate: startedLate,
                    manuallyClockedOut: true,
                    cashSale: nil,
                    cashInHand: nil,
                    overShort: nil,
                    creditCard: nil
                )
                try await firebaseService.createShift(userId: managerUserId, locationId: locationId, shift: shift)
                
                var updatedEmployee = employee
                updatedEmployee.currentShiftStatus = .clockedIn
                updatedEmployee.shiftHistory.append(shift.id)
                // Preserve password when updating
                try await firebaseService.updateEmployee(userId: managerUserId, locationId: locationId, employee: updatedEmployee)
                
                currentShift = shift
                self.employee = updatedEmployee
            }
            
            // Reload data to ensure everything is in sync
            await loadData()
        } catch {
            errorMessage = "Failed to clock in: \(error.localizedDescription)"
        }
    }
    
    // Helper function to parse time string (HH:mm format) to Date
    private func parseTimeString(_ timeString: String) -> Date? {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              hour >= 0 && hour < 24,
              minute >= 0 && minute < 60 else {
            return nil
        }
        
        let calendar = Calendar.current
        let now = Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }
    
    func clockOut() async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        guard var shift = currentShift else { return }
        do {
            shift.clockOutTime = Date()
            shift.manuallyClockedOut = true
            shift.isAutoClockedOut = false
            try await firebaseService.updateShift(userId: managerUserId, locationId: locationId, shift: shift)
            
            var updatedEmployee = employee!
            updatedEmployee.currentShiftStatus = .clockedOut
            try await firebaseService.updateEmployee(userId: managerUserId, locationId: locationId, employee: updatedEmployee)
            
            currentShift = nil
            employee = updatedEmployee
            await loadData()
        } catch {
            errorMessage = "Failed to clock out: \(error.localizedDescription)"
        }
    }
    
    // Auto clock out shifts that are past their scheduled end time + 10 minutes
    func checkAndAutoClockOut() async {
        guard let managerUserId = managerUserId else { return }
        
        let activeShifts = allShifts.filter { $0.isActive }
        
        for var shift in activeShifts {
            if shift.shouldAutoClockOut {
                // Auto clock out this shift
                shift.clockOutTime = shift.scheduledEndTime // Use scheduled end time, not actual time
                shift.isAutoClockedOut = true
                shift.manuallyClockedOut = false
                
                do {
                    try await firebaseService.updateShift(userId: managerUserId, locationId: locationId, shift: shift)
                    
                    // Update employee status if this is the current shift
                    if shift.id == currentShift?.id {
                        var updatedEmployee = employee!
                        updatedEmployee.currentShiftStatus = .clockedOut
                        try await firebaseService.updateEmployee(userId: managerUserId, locationId: locationId, employee: updatedEmployee)
                        employee = updatedEmployee
                        currentShift = nil
                    }
                } catch {
                    print("Failed to auto clock out shift \(shift.id): \(error.localizedDescription)")
                }
            }
        }
        
        // Reload data to reflect changes
        await loadData()
    }
    
    func completeTask(_ task: WorkTask, imageDataList: [Data], note: String? = nil) async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        do {
            print("🟢 Starting task completion for task: \(task.id) with \(imageDataList.count) images")
            
            // Upload all images to Firebase Storage in parallel
            let imageURLs = try await firebaseService.uploadTaskImages(
                imageDataList: imageDataList,
                taskId: task.id,
                userId: managerUserId,
                locationId: locationId
            )
            print("🟢 All images uploaded: \(imageURLs.count) URLs")
            
            // Update task with completion for this specific employee
            var updatedTask = task
            let completion = TaskCompletion(
                employeeId: employeeId,
                imageURLs: imageURLs,
                timestamp: Date(),
                note: note
            )
            updatedTask.setEmployeeCompletion(completion)
            
            print("🟢 Updating task in Firestore...")
            try await firebaseService.updateTask(userId: managerUserId, locationId: locationId, task: updatedTask)
            // Also update the manager-level mirror so dashboard score bars
            // (which read from `users/{uid}/tasks`) reflect the completion.
            // Failures here are logged but don't fail the whole completion —
            // the per-location write is the source of truth for the employee.
            do {
                try await firebaseService.updateManagerTask(userId: managerUserId, task: updatedTask)
            } catch {
                print("⚠️ Failed to mirror completion to manager-level task: \(error.localizedDescription)")
            }
            print("🟢 Task updated successfully")
            
            // Update local tasks array immediately for instant UI feedback
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updatedTask
                print("🟢 Local tasks array updated")
            }
            
            // Also reload data to ensure sync (observer will also update)
            await loadData()
            print("🟢 Data reloaded, tasks count: \(tasks.count)")
        } catch {
            print("🔴 Error completing task: \(error.localizedDescription)")
            errorMessage = "Failed to complete task: \(error.localizedDescription)"
        }
    }
    
    // Background upload function that continues even after view dismissal
    func completeTaskInBackground(_ task: WorkTask, imageDataList: [Data], note: String? = nil) {
        // Capture necessary values before starting background task
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        let currentLocationId = locationId
        let currentEmployeeId = employeeId
        
        // Start background task that continues even after view dismissal
        Task(priority: .userInitiated) {
            do {
                print("🟢 Starting background task completion for task: \(task.id) with \(imageDataList.count) images")
                
                // Upload all images to Firebase Storage in parallel
                let imageURLs = try await firebaseService.uploadTaskImages(
                    imageDataList: imageDataList,
                    taskId: task.id,
                    userId: managerUserId,
                    locationId: currentLocationId
                )
                print("🟢 All images uploaded in background: \(imageURLs.count) URLs")
                
                // Update task with completion for this specific employee
                var updatedTask = task
                let completion = TaskCompletion(
                    employeeId: currentEmployeeId,
                    imageURLs: imageURLs,
                    timestamp: Date(),
                    note: note
                )
                updatedTask.setEmployeeCompletion(completion)
                
                print("🟢 Updating task in Firestore (background)...")
                try await firebaseService.updateTask(userId: managerUserId, locationId: currentLocationId, task: updatedTask)
                // Mirror to manager-level task so dashboard score bars reflect
                // the completion. Failures are non-fatal.
                do {
                    try await firebaseService.updateManagerTask(userId: managerUserId, task: updatedTask)
                } catch {
                    print("⚠️ Failed to mirror completion to manager-level task: \(error.localizedDescription)")
                }
                print("🟢 Task updated successfully in background")
                
                // Update local tasks array on main thread
                await MainActor.run {
                    if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                        self.tasks[index] = updatedTask
                        print("🟢 Local tasks array updated")
                    }
                    // Reload data to ensure sync
                    Task {
                        await self.loadData()
                    }
                }
            } catch {
                print("🔴 Error completing task in background: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to complete task: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updateShift(_ shift: Shift) async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        do {
            try await firebaseService.updateShift(userId: managerUserId, locationId: locationId, shift: shift)
            // Reload last location register close if this shift closed a register
            if shift.registerClosedAt != nil {
                await loadLastLocationRegisterClose(managerUserId: managerUserId, locationId: locationId)
            }
            await loadData()
        } catch {
            errorMessage = "Failed to update shift: \(error.localizedDescription)"
        }
    }
    
    func loadLastLocationRegisterClose(managerUserId: String, locationId: String) async {
        do {
            // Fetch all shifts for this location
            let allLocationShifts = try await firebaseService.fetchShifts(userId: managerUserId, locationId: locationId)
            
            // Also ensure employees are loaded for getting names
            if allEmployees.isEmpty {
                allEmployees = try await firebaseService.fetchEmployees(userId: managerUserId, locationId: locationId)
            }
            
            // Find the most recent shift with a closed register (registerClosedAt is not nil)
            // Exclude the current employee's active shift to avoid showing their own register
            let closedRegisters = allLocationShifts
                .filter { shift in
                    // Must have registerClosedAt and not be the current employee's active shift
                    shift.registerClosedAt != nil &&
                    !(shift.employeeId == employeeId && shift.isActive)
                }
                .sorted { shift1, shift2 in
                    // Sort by registerClosedAt descending (most recent first)
                    guard let date1 = shift1.registerClosedAt,
                          let date2 = shift2.registerClosedAt else {
                        return false
                    }
                    return date1 > date2
                }
            
            // Get the most recent one
            lastLocationRegisterClose = closedRegisters.first
        } catch {
            print("⚠️ Failed to load last location register close: \(error.localizedDescription)")
            lastLocationRegisterClose = nil
        }
    }
    
    func createShiftForRegisterData(_ shift: Shift) async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        do {
            try await firebaseService.createShift(userId: managerUserId, locationId: locationId, shift: shift)
            await loadData()
        } catch {
            errorMessage = "Failed to create shift: \(error.localizedDescription)"
        }
    }
    
    /// Multi-terminal templates keyed by terminal number. Populated
    /// **only** when this location runs multiple lottery terminals.
    /// For single-terminal locations this dictionary stays empty and
    /// the legacy `lotteryTemplate` is the source of truth — that keeps
    /// the existing call sites byte-for-byte unchanged.
    @Published var lotteryTemplates: [Int: LotteryFormTemplate] = [:]

    /// True iff the loaded `Location` has been configured with > 1
    /// lottery terminal. Drives whether the multi-terminal employee
    /// flow lights up at all. Reads through to `Location` so we don't
    /// hold a stale copy.
    var hasMultipleLotteryTerminals: Bool {
        location?.hasMultipleLotteryTerminals ?? false
    }

    func loadLotteryTemplate() async {
        guard let managerUserId = managerUserId else { return }

        // Multi-terminal path: pull every active terminal's template
        // in parallel. Archived terminals (in
        // `Location.lotteryArchivedTerminals`) are skipped so the
        // employee never sees them on close-out, but their docs stay
        // in Firestore for re-enable later.
        if let location = location, location.hasMultipleLotteryTerminals {
            let archived = Set(location.lotteryArchivedTerminals ?? [])
            let active = location.activeLotteryTerminalNumbers.filter { !archived.contains($0) }
            var loaded: [Int: LotteryFormTemplate] = [:]

            await withTaskGroup(of: (Int, LotteryFormTemplate?).self) { group in
                for terminal in active {
                    group.addTask { [firebaseService, locationId] in
                        let template = try? await firebaseService.fetchLotteryFormTemplate(
                            userId: managerUserId,
                            locationId: locationId,
                            terminalNumber: terminal
                        )
                        return (terminal, template)
                    }
                }
                for await (terminal, template) in group {
                    if let template = template {
                        loaded[terminal] = template
                    }
                }
            }

            lotteryTemplates = loaded
            // Keep the legacy `lotteryTemplate` pointing at terminal 1
            // so existing nil/empty checks (e.g. EmployeeLotteryView's
            // empty-state branch) still behave correctly when the
            // manager hasn't filled in terminal 1 yet.
            lotteryTemplate = loaded[1]
            return
        }

        // Single-terminal / legacy path — unchanged from before.
        do {
            lotteryTemplate = try await firebaseService.fetchLotteryFormTemplate(userId: managerUserId, locationId: locationId)
            lotteryTemplates = [:]
        } catch {
            print("Failed to load lottery template: \(error.localizedDescription)")
            lotteryTemplate = nil
            lotteryTemplates = [:]
        }
    }
    
    /// Resolve the in-memory template for a given terminal. `nil`
    /// means "the legacy single-terminal template" — i.e. the same
    /// `lotteryTemplate` that pre-dates multi-terminal support, which
    /// the storage layer treats as terminal 1. Non-nil reads from
    /// `lotteryTemplates`. Returns nil if nothing's loaded.
    private func template(for terminalNumber: Int?) -> LotteryFormTemplate? {
        guard let terminalNumber = terminalNumber else { return lotteryTemplate }
        return lotteryTemplates[terminalNumber]
    }

    /// Write the given template back into in-memory state. Mirror of
    /// `template(for:)` — if the caller passes nil we update the
    /// legacy `lotteryTemplate`; otherwise we update the dictionary.
    private func setTemplate(_ template: LotteryFormTemplate, for terminalNumber: Int?) {
        if let terminalNumber = terminalNumber {
            lotteryTemplates[terminalNumber] = template
            // Multi-terminal locations also keep `lotteryTemplate`
            // pointing at terminal 1 so legacy nil/empty checks behave.
            if terminalNumber == 1 {
                lotteryTemplate = template
            }
        } else {
            lotteryTemplate = template
        }
    }

    func updateLotteryRowEndingNumber(
        rowId: String,
        endingNumber: String,
        terminalNumber: Int? = nil
    ) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        guard var template = template(for: terminalNumber) else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Lottery template not loaded"])
        }

        // Find and update the row, then persist the whole template.
        // We keep the per-keystroke save behaviour the original
        // single-terminal code had so an interrupted session doesn't
        // lose the employee's input — same trade-off, just scoped to
        // the right terminal.
        if let index = template.rows.firstIndex(where: { $0.id == rowId }) {
            template.rows[index].endingNumber = endingNumber
            try await firebaseService.saveLotteryFormTemplate(
                userId: managerUserId,
                locationId: locationId,
                template: template
            )
            setTemplate(template, for: terminalNumber)
        }
    }
    
    // Validation result for incomplete rows
    struct ValidationResult {
        let incompleteRows: [IncompleteRow]
        let hasIncompleteRows: Bool
        
        struct IncompleteRow {
            let binNumber: String
            let gameNumber: String
            let missingFields: [String]
        }
    }
    
    /// Validate lottery form for incomplete rows. `terminalNumber: nil`
    /// validates against the legacy single-terminal template (existing
    /// behaviour); a non-nil value validates that specific terminal's
    /// template instead.
    func validateLotteryForm(terminalNumber: Int? = nil) async -> ValidationResult {
        guard let template = template(for: terminalNumber) else {
            return ValidationResult(incompleteRows: [], hasIncompleteRows: false)
        }
        
        var incompleteRows: [ValidationResult.IncompleteRow] = []
        
        for (index, row) in template.rows.enumerated() {
            var missingFields: [String] = []
            
            // Check for missing required fields
            if row.beginningNumber.isEmpty {
                missingFields.append("Beginning #")
            }
            if row.endingNumber.isEmpty {
                missingFields.append("Ending #")
            }
            if row.value.isEmpty {
                missingFields.append("Value")
            }
            if row.tickets.isEmpty {
                missingFields.append("Tickets")
            }
            
            // Only include rows that have at least one missing field
            if !missingFields.isEmpty {
                incompleteRows.append(ValidationResult.IncompleteRow(
                    binNumber: String(index + 1),
                    gameNumber: row.gameNumber.isEmpty ? "N/A" : row.gameNumber,
                    missingFields: missingFields
                ))
            }
        }
        
        return ValidationResult(
            incompleteRows: incompleteRows,
            hasIncompleteRows: !incompleteRows.isEmpty
        )
    }
    
    /// Close a lottery shift for either:
    ///   • the legacy single-terminal location (`terminalNumber == nil`,
    ///     which keeps every existing call site working byte-for-byte),
    ///     or
    ///   • a specific terminal at a multi-terminal location
    ///     (`terminalNumber == 1, 2, 3, …`).
    ///
    /// Multi-terminal locations call this once **per terminal** the
    /// employee actually worked. Untouched terminals are simply not
    /// invoked, so their beginning numbers carry over to the next
    /// shift unchanged — that's the "skip allowed" behaviour locked in
    /// during planning.
    func closeLotteryShift(
        formData: [String: String],
        onlineTotals: [String],
        onlineCashes: [String],
        instantCashes: [String],
        imageData: Data?,
        registerCash: String?,
        cashInHand: Double,
        skipValidation: Bool = false,
        terminalNumber: Int? = nil
    ) async throws -> LotteryForm {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }

        // Require an active shift (employee must be clocked in)
        guard let shift = currentShift, shift.isActive else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "You must be clocked in to submit a lottery form. Please clock in first."])
        }

        // 0. Reload the template we're about to mutate so we pick up
        // any keystroke-level saves (`updateLotteryRowEndingNumber`)
        // the form view kicked off while the employee was typing.
        if let latestTemplate = try? await firebaseService.fetchLotteryFormTemplate(
            userId: managerUserId,
            locationId: locationId,
            terminalNumber: terminalNumber
        ) {
            setTemplate(latestTemplate, for: terminalNumber)
        }

        guard var template = template(for: terminalNumber) else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Lottery template not loaded"])
        }

        // Validate before proceeding (unless validation is skipped)
        if !skipValidation {
            let validation = await validateLotteryForm(terminalNumber: terminalNumber)
            if validation.hasIncompleteRows {
                // Create a detailed error message
                var errorMessage = "Some rows have missing fields:\n\n"
                for incompleteRow in validation.incompleteRows {
                    errorMessage += "Bin #\(incompleteRow.binNumber)"
                    if !incompleteRow.gameNumber.isEmpty && incompleteRow.gameNumber != "N/A" {
                        errorMessage += " (Game #\(incompleteRow.gameNumber))"
                    }
                    errorMessage += ": Missing \(incompleteRow.missingFields.joined(separator: ", "))\n"
                }
                errorMessage += "\nYou can still close the shift, but these rows will not be included in calculations."

                // Throw a validation error that can be caught and handled
                throw NSError(
                    domain: "Oplix",
                    code: 100, // Special code for validation errors
                    userInfo: [
                        NSLocalizedDescriptionKey: errorMessage,
                        "validationResult": validation
                    ]
                )
            }
        }
        
        // 1. Calculate values for each row and update template with calculated sold/dollars/books
        // This uses the ending numbers that the employee entered
        let reverseOrder = template.reverseOrder
        
        // Calculate and store sold/dollars/books for each row
        for index in template.rows.indices {
            let row = template.rows[index]
            
            // Only calculate if row has required data
            guard !row.beginningNumber.isEmpty,
                  !row.endingNumber.isEmpty,
                  !row.tickets.isEmpty else {
                continue
            }
            
            // Calculate sold and books
            let (sold, books) = LotteryCalculationService.calculateSoldAndBooks(
                beginning: row.beginningNumber,
                ending: row.endingNumber,
                tickets: row.tickets,
                reverseOrder: reverseOrder
            )
            
            // Calculate dollars (only if value exists)
            let dollars = !row.value.isEmpty ? LotteryCalculationService.calculateDollars(sold: sold, value: row.value) : 0
            
            // Update template row with calculated values
            template.rows[index].sold = String(sold)
            template.rows[index].dollar = String(dollars)
            template.rows[index].books = String(books)
        }
        
        // 2. Calculate template totals from updated rows
        let templateTotals = LotteryCalculationService.calculateTemplateTotals(
            rows: template.rows,
            reverseOrder: reverseOrder
        )
        
        print("🔢 Calculating totals with ending numbers:")
        for row in template.rows {
            if !row.beginningNumber.isEmpty && !row.endingNumber.isEmpty {
                print("  Row \(row.gameNumber.isEmpty ? "\(row.id.prefix(8))" : row.gameNumber): Beginning=\(row.beginningNumber), Ending=\(row.endingNumber), Tickets=\(row.tickets), Value=\(row.value)")
                print("    → Calculated: Sold=\(row.sold), Dollars=\(row.dollar), Books=\(row.books)")
            }
        }
        print("🔢 Calculated totals: Sold=\(templateTotals.totalSold), Dollars=\(templateTotals.totalDollars), Books=\(templateTotals.totalBooks)")
        
        // 2. Parse online total (use first value if multiple)
        let onlineTotal = onlineTotals.first.flatMap { Double($0.isEmpty ? "0" : $0) }
        
        // 3. Calculate shift summary
        let shiftSummary = LotteryCalculationService.calculateShiftSummary(
            templateTotals: templateTotals,
            onlineTotal: onlineTotal,
            onlineCashes: onlineCashes,
            instantCashes: instantCashes,
            registerCash: registerCash
        )
        
        // 4. Create form data with summary
        let formId = UUID().uuidString
        var updatedFormData = formData

        // Snapshot beginning + ending from the Firestore template we
        // just used for calculations — not from client `formData` alone.
        // The UI builds `formData["row_*"]` from debounced `rowValues`;
        // if the employee closes within the debounce window (or a save
        // fails), those keys can still match **Begin** while the book
        // actually advanced in Firestore. Overwriting from `template`
        // keeps the saved form consistent with totals and roll-forward.
        for row in template.rows {
            if !row.beginningNumber.isEmpty {
                updatedFormData["begin_\(row.id)"] = row.beginningNumber
            }
            updatedFormData["row_\(row.id)"] = row.endingNumber
        }
        
        // 5. Move ending numbers to beginning numbers in template, then clear ending numbers
        // Only move if ending number is not empty - keep beginning number if ending is empty
        for index in template.rows.indices {
            // Only move ending to beginning if ending number is not empty
            if !template.rows[index].endingNumber.isEmpty {
                template.rows[index].beginningNumber = template.rows[index].endingNumber
                template.rows[index].endingNumber = "" // Clear ending column for next shift
            }
            // If ending number is empty, keep the beginning number as is (don't move it)
        }
        
        // 6. Save updated template (with ending moved to beginning).
        // Re-stamp the terminal number on the value we save in case
        // the in-memory template was loaded before terminals existed
        // — guarantees the right doc id is used for the write.
        template.terminalNumber = terminalNumber ?? template.terminalNumber
        try await firebaseService.saveLotteryFormTemplate(
            userId: managerUserId,
            locationId: locationId,
            template: template
        )

        // 7. Update local template
        setTemplate(template, for: terminalNumber)
        
        // Counted cash enclosed for this shift (required before close).
        let overShort = cashInHand - shiftSummary.cashInBagNet

        // Convert ShiftSummary to ShiftSummaryData (do this before image upload)
        let summaryData = ShiftSummaryData(
            totalSold: shiftSummary.totalSold,
            totalDollars: shiftSummary.totalDollars,
            totalBooks: shiftSummary.totalBooks,
            instantTotal: shiftSummary.instantTotal,
            onlineTotal: shiftSummary.onlineTotal,
            totalSoldAmount: shiftSummary.totalSoldAmount,
            registerCash: shiftSummary.registerCash,
            totalCash: shiftSummary.totalCash,
            onlineCashes: shiftSummary.onlineCashes,
            instantCashes: shiftSummary.instantCashes,
            totalCashes: shiftSummary.totalCashes,
            cashInBag: shiftSummary.cashInBag,
            cashInBagNet: shiftSummary.cashInBagNet,
            overShort: overShort
        )
        
        // 8. Create and save lottery form with report (without image URL first for faster response).
        // Tag the form with the terminal it represents so multi-
        // terminal history can group + label correctly. nil keeps the
        // existing single-terminal write byte-identical.
        let form = LotteryForm(
            id: formId,
            locationId: locationId,
            shiftId: shift.id,
            formData: updatedFormData,
            notes: "",
            submittedAt: Date(),
            shiftSummary: summaryData,
            terminalNumber: terminalNumber
        )
        
        // Create form immediately (don't wait for image upload)
        try await firebaseService.createLotteryForm(userId: managerUserId, locationId: locationId, form: form)
        
        // Upload image in background and update form after (non-blocking)
        // Capture values needed for background task
        if let imageData = imageData {
            let backgroundManagerUserId = managerUserId
            let backgroundLocationId = locationId
            let backgroundFormId = formId
            let backgroundFirebaseService = firebaseService
            
            Task.detached(priority: .background) {
                do {
                    let imageURL = try await backgroundFirebaseService.uploadLotteryFormImage(
                        imageData: imageData,
                        formId: backgroundFormId,
                        userId: backgroundManagerUserId,
                        locationId: backgroundLocationId
                    )
                    
                    // Update form with image URL using Firestore merge
                    let db = Firestore.firestore()
                    try await db.collection("users")
                        .document(backgroundManagerUserId)
                        .collection("locations")
                        .document(backgroundLocationId)
                        .collection("lotteryForms")
                        .document(backgroundFormId)
                        .updateData(["formData.imageURL": imageURL])
                    
                    print("✅ Image uploaded and form updated successfully")
                } catch {
                    print("⚠️ Failed to upload image in background: \(error.localizedDescription)")
                    // Image upload failure doesn't prevent form submission
                }
            }
        }
        
        // Return the form with summary for display (immediately, without waiting for image)
        return form
    }
    
    func submitLotteryForm(formData: [String: String], notes: String, imageData: Data? = nil) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        guard let shift = currentShift else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active shift"])
        }
        
        let formId = UUID().uuidString
        var updatedFormData = formData
        
        // Upload image if provided
        if let imageData = imageData {
            let imageURL = try await firebaseService.uploadLotteryFormImage(
                imageData: imageData,
                formId: formId,
                userId: managerUserId,
                locationId: locationId
            )
            updatedFormData["imageURL"] = imageURL
        }
        
        let form = LotteryForm(
            id: formId,
            locationId: locationId,
            shiftId: shift.id,
            formData: updatedFormData,
            notes: notes,
            submittedAt: Date()
        )
        
        try await firebaseService.createLotteryForm(userId: managerUserId, locationId: locationId, form: form)
    }
    
    func updateLotteryFormOverShort(formId: String, overShort: Double) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        
        try await firebaseService.updateLotteryFormOverShort(
            userId: managerUserId,
            locationId: locationId,
            formId: formId,
            overShort: overShort
        )
    }
    
    func startObserving() {
        guard let managerUserId = managerUserId else { return }
        
        // Observe tasks for this location (employees can see all tasks at their location)
        firebaseService.observeTasks(userId: managerUserId, locationId: locationId) { [weak self] tasks in
            Task { @MainActor in
                guard let self = self else { return }
                // Filter to tasks assigned to this employee
                self.tasks = tasks.filter { $0.isAssignedTo(employeeId: self.employeeId) }
                print("🟢 Tasks updated via observer: \(self.tasks.count) tasks")
            }
        }
        
        // Observe shifts for this employee
        firebaseService.observeShifts(userId: managerUserId, locationId: locationId, employeeId: employeeId) { [weak self] shifts in
            Task { @MainActor in
                guard let self = self else { return }
                // Store all shifts for stats calculation
                self.allShifts = shifts
                // Show assigned shift (not started) or active shift (clocked in but not out)
                self.currentShift = shifts.first { $0.isAssigned || $0.isActive }
                
                // Check for shifts that need auto clock out
                await self.checkAndAutoClockOut()
            }
        }

        // Observe announcements addressed to this user. Server side
        // already wrote the recipient list; we just filter on the
        // client so each role only sees what was sent to them.
        announcementsListener?.remove()
        announcementsListener = firebaseService.observeAnnouncements(
            managerUserId: managerUserId
        ) { [weak self] all in
            Task { @MainActor in
                guard let self = self else { return }
                self.myAnnouncements = all.filter {
                    $0.recipientIds.contains(self.employeeId)
                }
            }
        }
    }

    func stopObserving() {
        announcementsListener?.remove()
        announcementsListener = nil
    }

    deinit {
        announcementsListener?.remove()
    }

    // MARK: - Announcements

    /// Unread count for the home-screen badge. Counts only the
    /// announcements this user hasn't tapped into yet.
    var unreadAnnouncementCount: Int {
        myAnnouncements.filter { $0.isUnread(for: employeeId) }.count
    }

    /// Most-recent announcement, used by the home-screen preview card.
    /// nil when the user has never received one.
    var latestAnnouncement: Announcement? {
        myAnnouncements.first
    }

    /// Mark a single announcement as read for the current user. Safe
    /// to call repeatedly; the Firestore write is a no-op when the
    /// user is already in `readBy`.
    func markAnnouncementRead(_ announcement: Announcement) async {
        guard let managerUserId = managerUserId else { return }
        // Optimistic local update so the badge drops immediately.
        if let idx = myAnnouncements.firstIndex(where: { $0.id == announcement.id }) {
            var copy = myAnnouncements[idx]
            var by = copy.readBy ?? [:]
            if by[employeeId] == nil {
                by[employeeId] = Date()
                copy.readBy = by
                myAnnouncements[idx] = copy
            }
        }
        do {
            try await firebaseService.markAnnouncementRead(
                managerUserId: managerUserId,
                announcementId: announcement.id,
                userId: employeeId
            )
        } catch {
            print("⚠️ Failed to mark announcement \(announcement.id) read: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Task Management Methods
    
    func loadAllTasks() async {
        guard let managerUserId = managerUserId else { return }
        do {
            allTasks = try await firebaseService.fetchTasks(userId: managerUserId, locationId: locationId)
        } catch {
            errorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }
    
    func loadAllEmployees() async {
        guard let managerUserId = managerUserId else { return }
        do {
            allEmployees = try await firebaseService.fetchEmployees(userId: managerUserId, locationId: locationId)
        } catch {
            errorMessage = "Failed to load employees: \(error.localizedDescription)"
        }
    }
    
    func createTask(description: String, assignedEmployeeId: String?) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        
        let task = WorkTask(
            id: UUID().uuidString,
            description: description,
            assignedEmployeeIds: assignedEmployeeId != nil ? [assignedEmployeeId!] : [],
            locationId: locationId,
            employeeCompletions: [:]
        )
        
        try await firebaseService.createTask(userId: managerUserId, locationId: locationId, task: task)
        await loadAllTasks()
    }
    
    func updateTask(_ task: WorkTask) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        
        try await firebaseService.updateTask(userId: managerUserId, locationId: locationId, task: task)
        // Mirror to manager-level so dashboard score bars stay in sync.
        do {
            try await firebaseService.updateManagerTask(userId: managerUserId, task: task)
        } catch {
            print("⚠️ Failed to mirror task update to manager-level: \(error.localizedDescription)")
        }
        await loadAllTasks()
    }
    
    func deleteTask(_ task: WorkTask) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }

        try await firebaseService.deleteTask(userId: managerUserId, locationId: locationId, taskId: task.id)
        // Mirror the delete to the manager-level collection so dashboard
        // score bars stop counting this task immediately. Non-fatal.
        do {
            try await firebaseService.deleteManagerTask(userId: managerUserId, taskId: task.id)
        } catch {
            print("⚠️ Failed to delete manager-level mirror for task: \(error.localizedDescription)")
        }
        await loadAllTasks()
    }
}

