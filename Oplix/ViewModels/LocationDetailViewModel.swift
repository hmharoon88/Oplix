//
//  LocationDetailViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class LocationDetailViewModel: ObservableObject {
    @Published var location: Location?
    @Published var employees: [Employee] = []
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
    private let locationId: String
    
    init(userId: String, locationId: String) {
        self.userId = userId
        self.locationId = locationId
        print("🟢 LocationDetailViewModel init - userId: \(userId), locationId: \(locationId)")
        print("🟢 isLoading: \(isLoading)")
    }
    
    func loadData() async {
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
            employees = try await employeesTask
            print("🟢 Employees fetched: \(employees.count)")
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
        print("🟢 loadData completed - isLoading: \(isLoading), location: \(location?.name ?? "nil")")
    }
    
    func createEmployee(name: String, password: String, workingHoursStart: String? = nil, workingHoursEnd: String? = nil, weeklySchedule: WeeklySchedule? = nil, hourlyRate: Double? = nil, canTakeRegister: Bool = false, canSubmitLottery: Bool = false) async throws -> (username: String, email: String, password: String) {
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
                    role: .employee,
                    locationId: locationId,
                    managerUserId: userId
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
            assignedLocationIds: [locationId], // Add to assigned locations
            hourlyRate: hourlyRate
        )
        employee.canTakeRegister = canTakeRegister
        employee.canSubmitLottery = canSubmitLottery
        
        // Create at manager level first
        try await firebaseService.createManagerEmployee(userId: userId, employee: employee)
        
        // Also create in location subcollection for backward compatibility
        try await firebaseService.createEmployee(userId: userId, locationId: locationId, employee: employee)
        
        // Update location
        var updatedLocation = location!
        updatedLocation.employees.append(createdUser.id)
        try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
        
        await loadData()
        
        return (username: finalUsername, email: email, password: password)
    }
    
    func updateEmployee(_ employee: Employee) async throws {
        try await firebaseService.updateEmployee(userId: userId, locationId: locationId, employee: employee)
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
            // First, unassign all tasks from this employee
            let tasksToUnassign = tasks.filter { $0.isAssignedTo(employeeId: employee.id) }
            for task in tasksToUnassign {
                await unassignTask(task, fromEmployeeId: employee.id)
            }
            
            // Delete employee from Firestore (including User document)
            try await firebaseService.deleteEmployee(userId: userId, locationId: locationId, employeeId: employee.id)
            
            // Remove employee ID from location's employees array
            var updatedLocation = location!
            updatedLocation.employees.removeAll { $0 == employee.id }
            try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
            
            await loadData()
        } catch {
            errorMessage = "Failed to delete employee: \(error.localizedDescription)"
        }
    }
    
    func createTask(description: String, assignedToEmployeeId: String?) async {
        do {
            let assignedIds = assignedToEmployeeId != nil ? [assignedToEmployeeId!] : []
            let task = WorkTask(
                id: UUID().uuidString,
                description: description,
                assignedEmployeeIds: assignedIds,
                locationId: locationId, // Set primary location
                assignedLocationIds: [locationId], // Add to assigned locations
                employeeCompletions: [:]
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
            await loadData()
        } catch {
            errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }
    
    func deleteTask(_ task: WorkTask) async {
        do {
            try await firebaseService.deleteTask(userId: userId, locationId: locationId, taskId: task.id)
            var updatedLocation = location!
            updatedLocation.tasks.removeAll { $0 == task.id }
            try await firebaseService.updateLocation(userId: userId, location: updatedLocation)
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
    
    func createDocument(name: String, fileData: Data, fileName: String, fileType: String, expiryDate: Date?, uploadedBy: String) async throws {
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
            uploadedBy: uploadedBy
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
    
    func loadLotteryFormTemplate() async -> [LotteryFormTemplateRow] {
        do {
            if let template = try await firebaseService.fetchLotteryFormTemplate(userId: userId, locationId: locationId) {
                return template.rows
            }
        } catch {
            print("🔴 Failed to load lottery form template: \(error.localizedDescription)")
        }
        return []
    }
    
    func saveLotteryFormTemplate(rows: [LotteryFormTemplateRow]) async throws {
        let template = LotteryFormTemplate(locationId: locationId, rows: rows)
        try await firebaseService.saveLotteryFormTemplate(userId: userId, locationId: locationId, template: template)
    }
}

