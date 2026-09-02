//
//  LocationDetailViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation
import FirebaseAuth

@MainActor
class LocationDetailViewModel: ObservableObject {
    @Published var location: Location?
    @Published var employees: [Employee] = []
    @Published var supervisors: [Employee] = [] // Supervisors at this location

    /// Employees and supervisors assigned to this location (for payroll sheet).
    var payrollStaff: [Employee] {
        (employees + supervisors).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @Published var tasks: [WorkTask] = []
    @Published var shifts: [Shift] = []
    @Published var lotteryForms: [LotteryForm] = []
    @Published var documents: [Document] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var selectedTab: LocationTab = .employees
    
    enum LocationTab {
        case employees, tasks, lottery
    }
    
    private let firebaseService = FirebaseService.shared
    let userId: String
    let locationId: String
    private var isLoadDataInProgress = false // Prevent concurrent loadData calls
    private var hasLoadedData = false // Track if data has been successfully loaded
    private var currentUserRole: User.UserRole? // Store current user's role to avoid fetching
    private var currentUserId: String? // Store current user ID to skip fetching
    private var userRoleCache: [String: User.UserRole] = [:] // Persistent cache across loadData calls
    
    // Static cache shared across all instances to prevent fetching same user multiple times
    private static var globalUserRoleCache: [String: User.UserRole] = [:]
    private static var cacheLock = NSLock()
    
    // Helper function for async-safe cache access
    private static func withCacheLock<T>(_ operation: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return operation()
    }

    /// Public hook so role changes made outside the location screens
    /// (e.g. promote/demote from `EditManagerEmployeeView`) can keep the
    /// shared role cache consistent. Without this the next location
    /// screen would still bucket the affected user under their old role
    /// until a fresh User-doc fetch happens.
    static func setCachedRole(_ role: User.UserRole?, for employeeId: String) {
        withCacheLock {
            if let role = role {
                globalUserRoleCache[employeeId] = role
            } else {
                globalUserRoleCache.removeValue(forKey: employeeId)
            }
        }
    }
    
    init(userId: String, locationId: String, currentUserRole: User.UserRole? = nil) {
        self.userId = userId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        self.currentUserId = Auth.auth().currentUser?.uid
        print("🟢 LocationDetailViewModel init - userId: \(userId), locationId: \(locationId), currentUserRole: \(currentUserRole?.rawValue ?? "nil"), currentUserId: \(currentUserId ?? "nil")")
        print("🟢 isLoading: \(isLoading)")
    }
    
    func loadData() async {
        // Prevent concurrent calls
        guard !isLoadDataInProgress else {
            print("⚠️ loadData already in progress, skipping...")
            return
        }
        
        // If data has already been loaded and we have location/employees, don't reload
        // This prevents loops from view re-renders
        // But allow reload if location is nil (data might have been cleared)
        if hasLoadedData && location != nil && !employees.isEmpty {
            print("⚠️ loadData skipped - data already loaded (location: \(location?.name ?? "nil"), employees: \(employees.count))")
            return
        }
        
        isLoadDataInProgress = true
        print("🟢 loadData called - userId: \(userId), locationId: \(locationId)")
        isLoading = true
        errorMessage = nil
        do {
            print("🟢 Fetching location data...")
            async let locationTask = firebaseService.fetchLocation(userId: userId, locationId: locationId)
            async let employeesTask = firebaseService.fetchEmployees(userId: userId, locationId: locationId)
            async let tasksTask = firebaseService.fetchTasks(userId: userId, locationId: locationId)
            async let shiftsTask = firebaseService.fetchShifts(userId: userId, locationId: locationId)
            async let lotteryTask = firebaseService.fetchLotteryForms(userId: userId, locationId: locationId)
            async let documentsTask = firebaseService.fetchDocuments(userId: userId, locationId: locationId)
            
            location = try await locationTask
            print("🟢 Location fetched: \(location?.name ?? "nil")")
            
            // Fetch employees - if empty, that's okay (might be timing issue)
            do {
                let allEmployees = try await employeesTask
                print("🟢 Employees fetched: \(allEmployees.count)")
                
                // Separate employees and supervisors based on their User role
                var employeesList: [Employee] = []
                var supervisorsList: [Employee] = []
                
                for employee in allEmployees {
                    // Check local cache first
                    if let cachedRole = userRoleCache[employee.id] {
                        if cachedRole == .supervisor {
                            supervisorsList.append(employee)
                        } else {
                            employeesList.append(employee)
                        }
                        continue
                    }
                    
                    // Check global static cache
                    let cachedRole: User.UserRole? = LocationDetailViewModel.withCacheLock {
                        return LocationDetailViewModel.globalUserRoleCache[employee.id]
                    }
                    if let cached = cachedRole {
                        userRoleCache[employee.id] = cached
                        if cached == .supervisor {
                            supervisorsList.append(employee)
                        } else {
                            employeesList.append(employee)
                        }
                        continue
                    }
                    
                    // Skip fetching current user's document if we know their role
                    if let currentUserId = currentUserId, employee.id == currentUserId, let role = currentUserRole {
                        print("⚠️ Skipping user fetch for current user: \(employee.id), using role: \(role.rawValue)")
                        userRoleCache[employee.id] = role
                        LocationDetailViewModel.withCacheLock {
                            LocationDetailViewModel.globalUserRoleCache[employee.id] = role
                        }
                        if role == .supervisor {
                            supervisorsList.append(employee)
                        } else {
                            employeesList.append(employee)
                        }
                        continue
                    }
                    
                    // Fetch user document to check role (only if not cached and not current user)
                    do {
                        let user = try await firebaseService.fetchUser(userId: employee.id)
                        let role = user.role
                        userRoleCache[employee.id] = role // Cache locally
                        LocationDetailViewModel.withCacheLock {
                            LocationDetailViewModel.globalUserRoleCache[employee.id] = role // Cache globally
                        }
                        if role == .supervisor {
                            supervisorsList.append(employee)
                        } else {
                            employeesList.append(employee)
                        }
                    } catch {
                        // If user fetch fails, assume employee (default)
                        employeesList.append(employee)
                        userRoleCache[employee.id] = .employee
                        LocationDetailViewModel.withCacheLock {
                            LocationDetailViewModel.globalUserRoleCache[employee.id] = .employee
                        }
                    }
                }
                
                employees = employeesList
                supervisors = supervisorsList
                print("🟢 Separated: \(employees.count) employees, \(supervisors.count) supervisors")
            } catch {
                print("⚠️ Warning: Failed to fetch employees: \(error.localizedDescription)")
                employees = [] // Set to empty array instead of failing
                supervisors = []
            }
            
            tasks = try await tasksTask
            print("🟢 Tasks fetched: \(tasks.count)")
            shifts = try await shiftsTask
            print("🟢 Shifts fetched: \(shifts.count)")
            lotteryForms = try await lotteryTask
            print("🟢 Lottery forms fetched: \(lotteryForms.count)")
            documents = try await documentsTask
            print("🟢 Documents fetched: \(documents.count)")
        } catch {
            print("🔴 Error loading data: \(error.localizedDescription)")
            print("🔴 Error type: \(type(of: error))")
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
        isLoadDataInProgress = false
        hasLoadedData = true // Mark data as loaded
        print("🟢 loadData completed - isLoading: \(isLoading), location: \(location?.name ?? "nil")")
    }
    
    // Method to force reload (for when data needs to be refreshed)
    func reloadData() async {
        hasLoadedData = false
        await loadData()
    }

    /// Fresh employee/supervisor lists (including loans) before opening payroll.
    func refreshEmployeesForPayroll() async {
        await reloadData()
    }
    
    // Method to reset loaded data flag (allows reloading when view reappears)
    func resetLoadedDataFlag() {
        hasLoadedData = false
    }
    
    func createEmployee(name: String, password: String, role: User.UserRole = .employee, workingHoursStart: String? = nil, workingHoursEnd: String? = nil, weeklySchedule: WeeklySchedule? = nil, is24Hours: Bool? = nil, hourlyRate: Double? = nil, canTakeRegister: Bool = false, canSubmitLottery: Bool = false, canEditSchedules: Bool? = nil, canManageTasks: Bool? = nil, canManageDocuments: Bool? = nil, canManagePayroll: Bool? = nil, managerEmail: String? = nil, managerPassword: String? = nil) async throws -> (username: String, email: String, password: String) {
        // Auto-generate username from name
        let baseUsername = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let cleanBaseUsername = baseUsername.isEmpty ? "employee" : baseUsername
        
        // Generate email from username
        var email = "\(cleanBaseUsername)@oplix.app"
        var finalUsername = cleanBaseUsername
        var user: User?
        var attempts = 0
        let maxAttempts = 10
        
        // Try to create user, if email exists, add unique suffix
        while attempts < maxAttempts {
            do {
                user = try await firebaseService.createUser(
                    email: email,
                    password: password,
                    username: finalUsername,
                    role: role,
                    locationId: locationId,
                    managerUserId: userId,
                    signOutAfterCreation: false
                )
                break // Success, exit loop
            } catch {
                // If email already exists, try with a unique suffix
                // Firebase Auth error code 17007 = email already in use
                let nsError = error as NSError
                let isEmailExistsError = (nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17007) ||
                                       (error.localizedDescription.lowercased().contains("email") && error.localizedDescription.lowercased().contains("already"))
                
                if isEmailExistsError && attempts < maxAttempts - 1 {
                    // Email already exists, try with numeric suffix (1, 2, 3, etc.)
                    let suffix = attempts + 1
                    finalUsername = "\(cleanBaseUsername)\(suffix)"
                    email = "\(finalUsername)@oplix.app"
                    attempts += 1
                    continue
                }
                // For other errors or max attempts reached, throw the error
                throw error
            }
        }
        
        // Ensure user was created successfully
        guard let createdUser = user else {
            throw NSError(domain: "LocationDetailViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user after \(maxAttempts) attempts"])
        }
        
        // Create Employee document using the user ID from Firebase Auth
        var employee = Employee(
            id: createdUser.id,
            name: name,
            username: finalUsername,
            locationId: locationId, // Set primary location
            managerUserId: userId, // Store manager's userId
            password: password, // Store password set by manager (optional)
            shiftHistory: [],
            currentShiftStatus: .clockedOut,
            workingHoursStart: workingHoursStart,
            workingHoursEnd: workingHoursEnd,
            weeklySchedule: weeklySchedule,
            is24Hours: is24Hours,
            assignedLocationIds: [locationId], // Add to assigned locations
            hourlyRate: hourlyRate
        )
        employee.canTakeRegister = canTakeRegister
        employee.canSubmitLottery = canSubmitLottery
        // Set supervisor-specific permissions
        employee.canEditSchedules = canEditSchedules
        employee.canManageTasks = canManageTasks
        employee.canManageDocuments = canManageDocuments
        employee.canManagePayroll = canManagePayroll
        
        try await firebaseService.createManagerEmployee(userId: userId, employee: employee)
        try await firebaseService.createEmployee(userId: userId, locationId: locationId, employee: employee)
        
        var updatedLocation = location!
        if !updatedLocation.employees.contains(createdUser.id) {
            updatedLocation.employees.append(createdUser.id)
        }
        try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
        
        resetLoadedDataFlag()
        await loadData()
        errorMessage = nil
        
        return (username: finalUsername, email: email, password: password)
    }
    
    func updateEmployee(_ employee: Employee) async throws {
        try await firebaseService.updateEmployee(userId: userId, locationId: locationId, employee: employee)
        // Reset the loaded data flag so loadData will refresh the data
        resetLoadedDataFlag()
        await loadData()
    }
    
    func updateEmployeePassword(employeeId: String, newPassword: String) async throws {
        // Get employee
        let employee = try await firebaseService.fetchEmployee(userId: userId, locationId: locationId, employeeId: employeeId)
        
        // Note: Firebase Auth doesn't allow updating another user's password from client SDK
        // This would require Admin SDK on the backend. For now, we'll update it in Firestore
        // The password in Firebase Auth would need to be updated via Firebase Console or Admin SDK
        // In a production app, you'd call a backend function that uses Admin SDK
        
        // Update password in Employee document
        var updatedEmployee = employee
        updatedEmployee.password = newPassword
        try await firebaseService.updateEmployee(userId: userId, locationId: locationId, employee: updatedEmployee)
        
        await loadData()
    }
    
    func deleteEmployee(_ employee: Employee) async {
        do {
            // First, unassign all tasks from this employee at this location.
            let tasksToUnassign = tasks.filter { $0.isAssignedTo(employeeId: employee.id) }
            for task in tasksToUnassign {
                await unassignTask(task, fromEmployeeId: employee.id)
            }

            // Same hard-delete flow as the Manager Employees tab — unassign
            // from every location the employee was at (cleans up each
            // location's subcollection + `Location.employees` array), then
            // remove from the manager-level mirror and delete the User
            // document. Without this the deleted employee keeps showing up
            // in the Employees tab.
            //
            // Defend against data drift by also unioning in the current
            // location id, so a stale `assignedLocationIds` that's missing
            // this location still gets cleaned.
            var locationsToUnassign = Set(employee.assignedLocationIds)
            locationsToUnassign.insert(locationId)
            for assignedLocId in locationsToUnassign {
                try? await firebaseService.unassignEmployeeFromLocation(
                    userId: userId,
                    employeeId: employee.id,
                    locationId: assignedLocId
                )
            }

            // Delete from manager-level employees + Firebase User doc.
            try await firebaseService.deleteManagerEmployee(userId: userId, employeeId: employee.id)

            // Keep the in-memory `location.employees` array honest so the
            // location detail screen reflects the change without waiting on
            // the next snapshot.
            if var updatedLocation = location {
                updatedLocation.employees.removeAll { $0 == employee.id }
                location = updatedLocation
            }

            await loadData()
        } catch {
            errorMessage = "Failed to delete employee: \(error.localizedDescription)"
        }
    }
    
    func createTask(description: String, assignedEmployeeIds: [String], frequency: TaskFrequency = .oneTime) async {
        do {
            let task = WorkTask(
                id: UUID().uuidString,
                description: description,
                assignedEmployeeIds: assignedEmployeeIds,
                locationId: locationId, // Set primary location
                assignedLocationIds: [locationId], // Add to assigned locations
                employeeCompletions: [:],
                frequency: frequency
            )
            
            // Create at manager level first
            try await firebaseService.createManagerTask(userId: userId, task: task)
            
            // Also create in location subcollection for backward compatibility
            try await firebaseService.createTask(userId: userId, locationId: locationId, task: task)
            
            var updatedLocation = location!
            updatedLocation.tasks.append(task.id)
            try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
            
            await loadData()
        } catch {
            errorMessage = "Failed to create task: \(error.localizedDescription)"
        }
    }
    
    func updateTask(_ task: WorkTask) async {
        do {
            try await firebaseService.updateTask(userId: userId, locationId: locationId, task: task)
            // Mirror to manager-level so dashboard score bars stay in sync.
            do {
                try await firebaseService.updateManagerTask(userId: userId, task: task)
            } catch {
                print("⚠️ Failed to mirror task update to manager-level: \(error.localizedDescription)")
            }
            await loadData()
        } catch {
            errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }

    /// Manager / supervisor approves or disapproves a specific completion
    /// photo on a task. Disapproved completions stop counting toward the
    /// "done" / score calculations (see `WorkTask.isCompletedBy`), and the
    /// employee will see the task flip back to incomplete with a "please
    /// redo" banner the next time they open it.
    ///
    /// - Parameters:
    ///   - task: The task containing the completion to review.
    ///   - employeeId: The employee whose photo is being reviewed.
    ///   - approved: `true` for Approve, `false` for Disapprove.
    ///   - note: Optional reason shown to the employee on disapproval.
    ///   - reviewerId: The signed-in manager / supervisor user id.
    func reviewCompletion(
        task: WorkTask,
        employeeId: String,
        approved: Bool,
        note: String?,
        reviewerId: String,
        /// When set (History tab), matches a specific archived submission.
        /// When nil (Current tab), reviews the employee's active completion.
        completionTimestamp: Date? = nil
    ) async {
        var updatedTask = task
        guard updatedTask.applyReview(
            employeeId: employeeId,
            completionTimestamp: completionTimestamp,
            approved: approved,
            note: note,
            reviewerId: reviewerId
        ) else {
            errorMessage = "Could not find a completion to review."
            return
        }

        if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
            tasks[index] = updatedTask
        }

        await updateTask(updatedTask)
    }
    
    func deleteTask(_ task: WorkTask) async {
        do {
            try await firebaseService.deleteTask(userId: userId, locationId: locationId, taskId: task.id)
            // Also delete the manager-level mirror so dashboard score bars
            // stop counting this task immediately. Non-fatal — even if this
            // fails, the per-location delete is the source of truth.
            do {
                try await firebaseService.deleteManagerTask(userId: userId, taskId: task.id)
            } catch {
                print("⚠️ Failed to delete manager-level mirror for task: \(error.localizedDescription)")
            }
            var updatedLocation = location!
            updatedLocation.tasks.removeAll { $0 == task.id }
            try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
            // Mirror the change locally so sequential deletes (e.g. bulk-delete
            // loop) don't read a stale `location.tasks` and re-add already-deleted
            // ids on the next write. `loadData()` is guarded and won't refetch
            // here, so we have to keep the in-memory copy in sync ourselves.
            location = updatedLocation
            tasks.removeAll { $0.id == task.id }
            await loadData()
        } catch {
            errorMessage = "Failed to delete task: \(error.localizedDescription)"
        }
    }
    
    func assignTask(_ task: WorkTask, toEmployeeId: String) async {
        var updatedTask = task
        if !updatedTask.assignedEmployeeIds.contains(toEmployeeId) {
            updatedTask.assignedEmployeeIds.append(toEmployeeId)
        }
        await updateTask(updatedTask)
    }
    
    func unassignTask(_ task: WorkTask, fromEmployeeId: String) async {
        var updatedTask = task
        updatedTask.assignedEmployeeIds.removeAll { $0 == fromEmployeeId }
        // Also remove completion if exists
        updatedTask.employeeCompletions.removeValue(forKey: fromEmployeeId)
        await updateTask(updatedTask)
    }
    
    func createShift(forEmployeeId: String) async {
        do {
            // Get employee to access working hours
            guard let employee = employees.first(where: { $0.id == forEmployeeId }) else {
                errorMessage = "Employee not found"
                return
            }
            
            // Calculate scheduled times based on weekly schedule or working hours
            var scheduledStartTime: Date?
            var scheduledEndTime: Date?
            
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            // Try to get working hours from weekly schedule first, then fallback to old workingHoursStart/End
            if let workingHours = employee.workingHours(for: today) {
                // Parse working hours
                if let startTime = parseTimeString(workingHours.start),
                   let endTime = parseTimeString(workingHours.end) {
                    scheduledStartTime = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                                       minute: calendar.component(.minute, from: startTime),
                                                       second: 0,
                                                       of: today)
                    scheduledEndTime = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                                     minute: calendar.component(.minute, from: endTime),
                                                     second: 0,
                                                     of: today)
                }
            }
            
            // Create an assigned shift (not yet started - clockInTime is nil)
            let shift = Shift(
                id: UUID().uuidString,
                employeeId: forEmployeeId,
                locationId: locationId,
                clockInTime: nil, // nil means assigned but not started
                clockOutTime: nil,
                assignedAt: Date(), // Track when shift was assigned for flagging
                acknowledged: false,
                scheduledStartTime: scheduledStartTime,
                scheduledEndTime: scheduledEndTime,
                isAutoClockedOut: false,
                startedLate: false,
                manuallyClockedOut: true,
                cashSale: nil,
                cashInHand: nil,
                overShort: nil,
                creditCard: nil
            )
            try await firebaseService.createShift(userId: userId, locationId: locationId, shift: shift)
            
            // Update employee's shift history
            if let employeeIndex = employees.firstIndex(where: { $0.id == forEmployeeId }) {
                var updatedEmployee = employees[employeeIndex]
                updatedEmployee.shiftHistory.append(shift.id)
                // Don't change currentShiftStatus - employee hasn't clocked in yet
                try await firebaseService.updateEmployee(userId: userId, locationId: locationId, employee: updatedEmployee)
            }
            
            await loadData()
        } catch {
            errorMessage = "Failed to create shift: \(error.localizedDescription)"
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
    
    func deleteShift(_ shift: Shift) async {
        do {
            try await firebaseService.deleteShift(userId: userId, locationId: locationId, shiftId: shift.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete shift: \(error.localizedDescription)"
        }
    }
    
    func acknowledgeShift(_ shift: Shift) async {
        do {
            var updatedShift = shift
            updatedShift.acknowledged = true
            try await firebaseService.updateShift(userId: userId, locationId: locationId, shift: updatedShift)
            await loadData()
        } catch {
            errorMessage = "Failed to acknowledge shift: \(error.localizedDescription)"
        }
    }
    
    func updateShift(_ shift: Shift) async {
        do {
            try await firebaseService.updateShift(userId: userId, locationId: locationId, shift: shift)
            await loadData()
        } catch {
            errorMessage = "Failed to update shift: \(error.localizedDescription)"
        }
    }
    
    func createDocument(name: String, fileData: Data, fileName: String, fileType: String, expiryDate: Date?, uploadedBy: String, dueReminder: DueDateReminder? = nil) async throws {
        // Upload file to Firebase Storage
        let fileURL = try await firebaseService.uploadDocument(
            fileData: fileData,
            fileName: fileName,
            fileType: fileType,
            userId: userId,
            locationId: locationId
        )
        
        // Create document record
        let document = Document(
            id: UUID().uuidString,
            locationId: locationId,
            name: name,
            fileURL: fileURL,
            fileType: fileType,
            uploadedAt: Date(),
            expiryDate: expiryDate,
            uploadedBy: uploadedBy,
            dueReminder: expiryDate != nil ? DueDateReminder.normalized(dueReminder) : nil
        )
        
        try await firebaseService.createDocument(userId: userId, locationId: locationId, document: document)
        await loadData()
    }
    
    func deleteDocument(_ document: Document) async {
        do {
            try await firebaseService.deleteDocument(userId: userId, locationId: locationId, documentId: document.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
        }
    }
    
    func startObserving() {
        firebaseService.observeTasks(userId: userId, locationId: locationId) { [weak self] tasks in
            guard let self = self else { return }
            self.tasks = tasks
        }
        
        firebaseService.observeLotteryForms(userId: userId, locationId: locationId) { [weak self] forms in
            guard let self = self else { return }
            self.lotteryForms = forms
        }
    }
    
    func loadLotteryFormTemplate() async -> (rows: [LotteryFormTemplateRow], lotteryRegisterAmount: String, reverseOrder: Bool) {
        do {
            if let template = try await firebaseService.fetchLotteryFormTemplate(userId: userId, locationId: locationId) {
                return (template.rows, template.lotteryRegisterAmount, template.reverseOrder)
            }
        } catch {
            print("🔴 Failed to load lottery form template: \(error.localizedDescription)")
        }
        return ([], "", false)
    }

    func saveLotteryFormTemplate(rows: [LotteryFormTemplateRow], lotteryRegisterAmount: String, reverseOrder: Bool) async throws {
        let template = LotteryFormTemplate(locationId: locationId, rows: rows, lotteryRegisterAmount: lotteryRegisterAmount, reverseOrder: reverseOrder)
        try await firebaseService.saveLotteryFormTemplate(userId: userId, locationId: locationId, template: template)
    }

    // MARK: - Multi-terminal lottery
    //
    // The methods below let the customization screen edit one template
    // per terminal independently. Single-terminal locations keep using
    // the legacy `loadLotteryFormTemplate` / `saveLotteryFormTemplate`
    // helpers above (which under the hood read/write doc id `template`,
    // which `FirebaseService` also treats as terminal 1).

    /// Load a specific terminal's template. Falls back to empty values
    /// when the terminal hasn't been configured yet (e.g. terminal 3
    /// after the manager just bumped the count from 2 to 3).
    func loadLotteryFormTemplate(terminalNumber: Int) async -> (rows: [LotteryFormTemplateRow], lotteryRegisterAmount: String, reverseOrder: Bool) {
        do {
            if let template = try await firebaseService.fetchLotteryFormTemplate(
                userId: userId,
                locationId: locationId,
                terminalNumber: terminalNumber
            ) {
                return (template.rows, template.lotteryRegisterAmount, template.reverseOrder)
            }
        } catch {
            print("🔴 Failed to load lottery template for terminal \(terminalNumber): \(error.localizedDescription)")
        }
        return ([], "", false)
    }

    /// Save a specific terminal's template. We always pass through
    /// `terminalNumber` so `FirebaseService` writes to the right doc id
    /// (`template` for terminal 1, `terminal_N` for the rest).
    func saveLotteryFormTemplate(
        terminalNumber: Int,
        rows: [LotteryFormTemplateRow],
        lotteryRegisterAmount: String,
        reverseOrder: Bool
    ) async throws {
        let template = LotteryFormTemplate(
            locationId: locationId,
            rows: rows,
            lotteryRegisterAmount: lotteryRegisterAmount,
            reverseOrder: reverseOrder,
            terminalNumber: terminalNumber
        )
        try await firebaseService.saveLotteryFormTemplate(
            userId: userId,
            locationId: locationId,
            template: template
        )
    }

    /// Update the location's `lotteryTerminalCount` and (optionally)
    /// the archived terminal list. Bumping the count exposes higher
    /// terminals in customization + employee close-out; lowering it
    /// archives those numbers (their template docs and history are
    /// preserved untouched in Firestore so the manager can re-enable).
    func updateLotteryTerminalCount(
        newCount: Int,
        archived: [Int]
    ) async throws {
        guard var updatedLocation = location else { return }
        updatedLocation.lotteryTerminalCount = max(1, newCount)
        updatedLocation.lotteryArchivedTerminals = archived.isEmpty ? nil : archived
        try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
        // Optimistic local update so the UI flips immediately without
        // waiting for the snapshot listener.
        location = updatedLocation
    }

    /// Require barcode scan for End # on lottery close (no keypad typing).
    func updateLotteryScanOnly(_ enabled: Bool) async throws {
        guard let current = location else { return }
        let updated = Location(copying: current, lotteryScanOnly: .some(enabled))
        try await firebaseService.updateLocation(userId: userId, location: updated)
        location = updated
    }

    /// Rename the location and/or change its address. We rebuild the
    /// whole `Location` struct (rather than mutating in place) because
    /// `name` and `address` are `let` properties on the model — keeping
    /// them immutable everywhere else of the app means callers can't
    /// accidentally rename a location mid-flow. We're explicit about it
    /// here.
    func updateLocationDetails(name: String, address: String) async throws {
        guard let current = location else { return }
        let updated = Location(
            copying: current,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await firebaseService.updateLocation(userId: userId, location: updated)
        location = updated
    }

    func updateNotificationSettings(_ settings: FacilityNotificationSettings) async throws {
        guard let current = location else { return }
        let normalized = FacilityNotificationSettings.normalized(settings)
        let updated = Location(copying: current, notificationSettings: normalized)
        try await firebaseService.updateLocation(userId: userId, location: updated)
        location = updated
    }
}

