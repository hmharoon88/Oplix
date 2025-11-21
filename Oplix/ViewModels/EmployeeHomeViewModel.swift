//
//  EmployeeHomeViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class EmployeeHomeViewModel: ObservableObject {
    @Published var employee: Employee?
    @Published var location: Location?
    @Published var tasks: [WorkTask] = []
    @Published var currentShift: Shift?
    @Published var allShifts: [Shift] = [] // Store all shifts for stats calculation
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    private let employeeId: String
    private let locationId: String
    private var managerUserId: String? // Will be set after fetching employee
    
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
    
    init(employeeId: String, locationId: String) {
        self.employeeId = employeeId
        self.locationId = locationId
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            // First fetch user to get managerUserId
            let user = try await firebaseService.fetchUser(userId: employeeId)
            guard let managerUserId = user.managerUserId else {
                errorMessage = "Manager user ID not found"
                isLoading = false
                return
            }
            self.managerUserId = managerUserId
            
            // Now fetch employee, location, and other data
            async let employeeTask = firebaseService.fetchEmployee(userId: managerUserId, locationId: locationId, employeeId: employeeId)
            async let locationTask = firebaseService.fetchLocation(userId: managerUserId, locationId: locationId)
            async let tasksTask = firebaseService.fetchTasks(userId: managerUserId, locationId: locationId)
            async let shiftsTask = firebaseService.fetchShifts(userId: managerUserId, locationId: locationId)
            
            employee = try await employeeTask
            location = try await locationTask
            let allTasks = try await tasksTask
            // Filter to tasks assigned to this employee
            tasks = allTasks.filter { $0.isAssignedTo(employeeId: employeeId) }
            let shifts = try await shiftsTask
            // Store all shifts for this employee
            allShifts = shifts.filter { $0.employeeId == employeeId }
            // Show assigned shift (not started) or active shift (clocked in but not out)
            currentShift = allShifts.first { $0.isAssigned || $0.isActive }
            
            // Check for shifts that need auto clock out
            await checkAndAutoClockOut()
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
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
        
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Calculate scheduled times for today
        let scheduledStartToday = calendar.date(bySettingHour: calendar.component(.hour, from: scheduledStart),
                                                 minute: calendar.component(.minute, from: scheduledStart),
                                                 second: 0,
                                                 of: today) ?? today
        let scheduledEndToday = calendar.date(bySettingHour: calendar.component(.hour, from: scheduledEnd),
                                              minute: calendar.component(.minute, from: scheduledEnd),
                                              second: 0,
                                              of: today) ?? today
        
        // Check if current time is within scheduled hours (no grace period - must be at or after start time)
        if now < scheduledStartToday || now > scheduledEndToday {
            errorMessage = "Clock in is only allowed during scheduled hours (\(startTimeStr) - \(endTimeStr))"
            return
        }
        
        // Check if starting late
        let startedLate = now > scheduledStartToday
        
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
    
    func completeTask(_ task: WorkTask, imageData: Data) async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        do {
            print("🟢 Starting task completion for task: \(task.id)")
            // Upload image to Firebase Storage
            let imageURL = try await firebaseService.uploadTaskImage(
                imageData: imageData,
                taskId: task.id,
                userId: managerUserId,
                locationId: locationId
            )
            print("🟢 Image uploaded to: \(imageURL)")
            
            // Update task with completion for this specific employee
            var updatedTask = task
            let completion = TaskCompletion(
                employeeId: employeeId,
                imageURL: imageURL,
                timestamp: Date()
            )
            updatedTask.employeeCompletions[employeeId] = completion
            
            print("🟢 Updating task in Firestore...")
            try await firebaseService.updateTask(userId: managerUserId, locationId: locationId, task: updatedTask)
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
    
    func updateShift(_ shift: Shift) async {
        guard let managerUserId = managerUserId else {
            errorMessage = "Manager user ID not found"
            return
        }
        do {
            try await firebaseService.updateShift(userId: managerUserId, locationId: locationId, shift: shift)
            await loadData()
        } catch {
            errorMessage = "Failed to update shift: \(error.localizedDescription)"
        }
    }
    
    func submitLotteryForm(formData: [String: String], notes: String) async throws {
        guard let managerUserId = managerUserId else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager user ID not found"])
        }
        guard let shift = currentShift else {
            throw NSError(domain: "Oplix", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active shift"])
        }
        
        let form = LotteryForm(
            id: UUID().uuidString,
            locationId: locationId,
            shiftId: shift.id,
            formData: formData,
            notes: notes,
            submittedAt: Date()
        )
        
        try await firebaseService.createLotteryForm(userId: managerUserId, locationId: locationId, form: form)
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
    }
}

