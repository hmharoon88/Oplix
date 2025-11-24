//
//  FirebaseService.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return try await fetchUser(userId: result.user.uid)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
    
    func updateUserPassword(email: String, newPassword: String) async throws {
        // Note: Firebase Auth doesn't allow updating another user's password from client SDK
        // This would require Admin SDK on the backend. For now, we'll update it in Firestore
        // and the password in Firebase Auth would need to be updated via Firebase Console or Admin SDK
        // In a production app, you'd call a backend function that uses Admin SDK
        
        // For now, we'll just update the password in Firestore (Employee model)
        // The actual Firebase Auth password would need to be updated separately
        // This is a limitation of client-side Firebase Auth
    }
    
    func createUser(email: String, password: String, username: String, role: User.UserRole, locationId: String?, managerUserId: String? = nil) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        let user = User(
            id: result.user.uid,
            username: username,
            role: role,
            locationId: locationId,
            managerUserId: managerUserId, // For employees: store the manager's userId
            createdAt: Date()
        )
        
        try await db.collection("users").document(user.id).setData(from: user)
        return user
    }
    
    func fetchUser(userId: String) async throws -> User {
        let document = try await db.collection("users").document(userId).getDocument()
        return try document.data(as: User.self)
    }
    
    func updateUser(userId: String, user: User) async throws {
        try await db.collection("users").document(userId).setData(from: user, merge: true)
    }
    
    func deleteAccount(userId: String, password: String) async throws {
        // Re-authenticate user to verify password
        guard let currentUser = Auth.auth().currentUser,
              let email = currentUser.email else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await currentUser.reauthenticate(with: credential)
        
        // Send email notification (requires backend function in production)
        // For now, we'll just log it
        print("📧 Account deletion requested for: \(email)")
        
        // Fetch all data to delete
        let locations = try await fetchLocations(userId: userId)
        let employees = try await fetchManagerEmployees(userId: userId)
        
        // Delete all locations (this cascades to employees, tasks, shifts, lottery forms)
        for location in locations {
            try? await deleteLocation(userId: userId, locationId: location.id)
        }
        
        // Delete all manager-level employees and their Firebase Auth accounts
        for employee in employees {
            // Delete employee's Firebase Auth account (requires Admin SDK in production)
            // For now, we'll delete the Firestore documents
            try? await deleteManagerEmployee(userId: userId, employeeId: employee.id)
            
            // Delete User document
            try? await db.collection("users").document(employee.id).delete()
        }
        
        // Delete all manager-level tasks
        let tasks = try await fetchManagerTasks(userId: userId)
        for task in tasks {
            try? await deleteManagerTask(userId: userId, taskId: task.id)
        }
        
        // Delete manager's User document
        try await db.collection("users").document(userId).delete()
        
        // Delete Firebase Auth account
        try await currentUser.delete()
    }
    
    func getCurrentUser() -> User? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        // In production, you'd fetch from Firestore, but for simplicity we'll return nil
        // and let the app fetch it after auth
        return nil
    }
    
    // MARK: - Locations (as subcollection under users)
    
    func fetchLocations(userId: String) async throws -> [Location] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Location.self)
        }
    }
    
    func fetchLocation(userId: String, locationId: String) async throws -> Location {
        let document = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .getDocument()
        return try document.data(as: Location.self)
    }
    
    func createLocation(userId: String, location: Location) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(location.id)
            .setData(from: location)
    }
    
    func updateLocation(userId: String, location: Location) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(location.id)
            .setData(from: location, merge: true)
    }
    
    func deleteLocation(userId: String, locationId: String) async throws {
        print("🔴 FirebaseService.deleteLocation - userId: \(userId), locationId: \(locationId)")
        
        // First, fetch all data to delete
        print("🔴 Fetching employees, tasks, shifts, and lottery forms...")
        
        var employees: [Employee] = []
        var tasks: [WorkTask] = []
        var shifts: [Shift] = []
        var lotteryForms: [LotteryForm] = []
        
        // Fetch with error handling - continue even if some fail
        do {
            employees = try await fetchEmployees(userId: userId, locationId: locationId)
            print("🔴 Fetched \(employees.count) employees")
        } catch {
            print("🔴 Warning: Failed to fetch employees: \(error.localizedDescription)")
            employees = []
        }
        
        do {
            tasks = try await fetchTasks(userId: userId, locationId: locationId)
            print("🔴 Fetched \(tasks.count) tasks")
        } catch {
            print("🔴 Warning: Failed to fetch tasks: \(error.localizedDescription)")
            tasks = []
        }
        
        do {
            shifts = try await fetchShifts(userId: userId, locationId: locationId)
            print("🔴 Fetched \(shifts.count) shifts")
        } catch {
            print("🔴 Warning: Failed to fetch shifts: \(error.localizedDescription)")
            shifts = []
        }
        
        do {
            lotteryForms = try await fetchLotteryForms(userId: userId, locationId: locationId)
            print("🔴 Fetched \(lotteryForms.count) lottery forms")
        } catch {
            print("🔴 Warning: Failed to fetch lottery forms: \(error.localizedDescription)")
            lotteryForms = []
        }
        
        print("🔴 Found \(employees.count) employees, \(tasks.count) tasks, \(shifts.count) shifts, \(lotteryForms.count) lottery forms")
        
        // Delete all employees (this also deletes their User documents)
        print("🔴 Deleting employees...")
        for employee in employees {
            do {
                try await deleteEmployee(userId: userId, locationId: locationId, employeeId: employee.id)
            } catch {
                print("🔴 Warning: Failed to delete employee \(employee.id): \(error.localizedDescription)")
                // Continue with other deletions
            }
        }
        
        // Delete all tasks and their images from Storage
        print("🔴 Deleting tasks and images...")
        let storage = Storage.storage()
        for task in tasks {
            // Delete task document
            do {
                try await deleteTask(userId: userId, locationId: locationId, taskId: task.id)
            } catch {
                print("🔴 Warning: Failed to delete task \(task.id): \(error.localizedDescription)")
            }
            
            // Delete task images from Storage if they exist
            // Note: Image path is task_images/{userId}/{locationId}/{taskId}.jpg (one per task)
            // Delete the image if any employee has completed the task
            if !task.employeeCompletions.isEmpty {
                let imagePath = "task_images/\(userId)/\(locationId)/\(task.id).jpg"
                let imageRef = storage.reference().child(imagePath)
                do {
                    try await imageRef.delete()
                    print("🔴 Deleted task image: \(imagePath)")
                } catch {
                    print("🔴 Warning: Failed to delete image \(imagePath): \(error.localizedDescription)")
                    // Continue with other deletions
                }
            }
        }
        
        // Delete all shifts
        print("🔴 Deleting shifts...")
        for shift in shifts {
            do {
                try await db.collection("users")
                    .document(userId)
                    .collection("locations")
                    .document(locationId)
                    .collection("shifts")
                    .document(shift.id)
                    .delete()
            } catch {
                print("🔴 Warning: Failed to delete shift \(shift.id): \(error.localizedDescription)")
                // Continue with other deletions
            }
        }
        
        // Delete all lottery forms
        print("🔴 Deleting lottery forms...")
        for form in lotteryForms {
            do {
                try await db.collection("users")
                    .document(userId)
                    .collection("locations")
                    .document(locationId)
                    .collection("lotteryForms")
                    .document(form.id)
                    .delete()
            } catch {
                print("🔴 Warning: Failed to delete lottery form \(form.id): \(error.localizedDescription)")
                // Continue with other deletions
            }
        }
        
        // Finally, delete the location document itself
        print("🔴 Deleting location document...")
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .delete()
        
        print("🔴 Location deletion completed successfully")
    }
    
    func observeLocations(userId: String, completion: @escaping ([Location]) -> Void) {
        let listener = db.collection("users")
            .document(userId)
            .collection("locations")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let locations = documents.compactMap { doc in
                    try? doc.data(as: Location.self)
                }
                completion(locations)
            }
        listeners["locations_\(userId)"] = listener
    }
    
    // MARK: - Manager-Level Employees (at user level)
    
    func fetchManagerEmployees(userId: String) async throws -> [Employee] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("employees")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Employee.self)
        }
    }
    
    func createManagerEmployee(userId: String, employee: Employee) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee)
    }
    
    func updateManagerEmployee(userId: String, employee: Employee) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee, merge: true)
    }
    
    func deleteManagerEmployee(userId: String, employeeId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employeeId)
            .delete()
        // Also delete User document
        try? await db.collection("users").document(employeeId).delete()
    }
    
    func assignEmployeeToLocation(userId: String, employeeId: String, locationId: String) async throws {
        // Get employee from manager collection
        let employeeDoc = try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employeeId)
            .getDocument()
        
        guard var employee = try? employeeDoc.data(as: Employee.self) else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Employee not found"])
        }
        
        // Add location to assigned locations
        if !employee.assignedLocationIds.contains(locationId) {
            employee.assignedLocationIds.append(locationId)
        }
        
        // Set primary locationId if not set
        if employee.locationId == nil {
            employee.locationId = locationId
        }
        
        // Update manager-level employee
        try await updateManagerEmployee(userId: userId, employee: employee)
        
        // Also create/update in location subcollection
        employee.locationId = locationId // Set primary location for backward compatibility
        try await createEmployee(userId: userId, locationId: locationId, employee: employee)
        
        // Update User document's locationId if not set
        let userDoc = try await db.collection("users").document(employeeId).getDocument()
        if var user = try? userDoc.data(as: User.self), user.locationId == nil {
            user.locationId = locationId
            try await db.collection("users").document(employeeId).setData(from: user, merge: true)
        }
        
        // Update location's employees list
        let locationDoc = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .getDocument()
        
        if var location = try? locationDoc.data(as: Location.self) {
            if !location.employees.contains(employeeId) {
                location.employees.append(employeeId)
                try await updateLocation(userId: userId, location: location)
            }
        }
    }
    
    func unassignEmployeeFromLocation(userId: String, employeeId: String, locationId: String) async throws {
        // Get employee from manager collection
        let employeeDoc = try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employeeId)
            .getDocument()
        
        guard var employee = try? employeeDoc.data(as: Employee.self) else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Employee not found"])
        }
        
        // Remove location from assigned locations
        employee.assignedLocationIds.removeAll { $0 == locationId }
        
        // Update manager-level employee
        try await updateManagerEmployee(userId: userId, employee: employee)
        
        // Delete from location subcollection
        try await deleteEmployee(userId: userId, locationId: locationId, employeeId: employeeId)
        
        // Update location's employees list
        let locationDoc = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .getDocument()
        
        if var location = try? locationDoc.data(as: Location.self) {
            location.employees.removeAll { $0 == employeeId }
            try await updateLocation(userId: userId, location: location)
        }
    }
    
    // MARK: - Employees (as subcollection under locations)
    
    func fetchEmployees(userId: String, locationId: String) async throws -> [Employee] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Employee.self)
        }
    }
    
    func fetchEmployee(userId: String, locationId: String, employeeId: String) async throws -> Employee {
        let document = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .document(employeeId)
            .getDocument()
        return try document.data(as: Employee.self)
    }
    
    func createEmployee(userId: String, locationId: String, employee: Employee) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee)
    }
    
    func updateEmployee(userId: String, locationId: String, employee: Employee) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee, merge: true)
    }
    
    func deleteEmployee(userId: String, locationId: String, employeeId: String) async throws {
        // Delete employee document from Firestore
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .document(employeeId)
            .delete()
        
        // Delete User document from Firestore
        // Note: Firebase Auth user account cannot be deleted from client SDK
        // This would require Admin SDK on the backend (Cloud Function)
        // For now, we delete the Firestore User document to allow recreation
        // The username generation logic handles email conflicts by adding unique suffixes
        try? await db.collection("users").document(employeeId).delete()
    }
    
    // MARK: - Manager-Level Tasks (at user level)
    
    func fetchManagerTasks(userId: String) async throws -> [WorkTask] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: WorkTask.self)
        }
    }
    
    func createManagerTask(userId: String, task: WorkTask) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task)
    }
    
    func updateManagerTask(userId: String, task: WorkTask) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task, merge: true)
    }
    
    func deleteManagerTask(userId: String, taskId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(taskId)
            .delete()
    }
    
    func assignTaskToLocation(userId: String, taskId: String, locationId: String) async throws {
        // Get task from manager collection
        let taskDoc = try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(taskId)
            .getDocument()
        
        guard var task = try? taskDoc.data(as: WorkTask.self) else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }
        
        // Add location to assigned locations
        if !task.assignedLocationIds.contains(locationId) {
            task.assignedLocationIds.append(locationId)
        }
        
        // Update manager-level task
        try await updateManagerTask(userId: userId, task: task)
        
        // Also create/update in location subcollection
        task.locationId = locationId // Set primary location for backward compatibility
        try await createTask(userId: userId, locationId: locationId, task: task)
        
        // Update location's tasks list
        let locationDoc = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .getDocument()
        
        if var location = try? locationDoc.data(as: Location.self) {
            if !location.tasks.contains(taskId) {
                location.tasks.append(taskId)
                try await updateLocation(userId: userId, location: location)
            }
        }
    }
    
    func unassignTaskFromLocation(userId: String, taskId: String, locationId: String) async throws {
        // Get task from manager collection
        let taskDoc = try await db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(taskId)
            .getDocument()
        
        guard var task = try? taskDoc.data(as: WorkTask.self) else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }
        
        // Remove location from assigned locations
        task.assignedLocationIds.removeAll { $0 == locationId }
        
        // Update manager-level task
        try await updateManagerTask(userId: userId, task: task)
        
        // Delete from location subcollection
        try await deleteTask(userId: userId, locationId: locationId, taskId: taskId)
        
        // Update location's tasks list
        let locationDoc = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .getDocument()
        
        if var location = try? locationDoc.data(as: Location.self) {
            location.tasks.removeAll { $0 == taskId }
            try await updateLocation(userId: userId, location: location)
        }
    }
    
    // MARK: - Tasks (as subcollection under locations)
    
    func fetchTasks(userId: String, locationId: String) async throws -> [WorkTask] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: WorkTask.self)
        }
    }
    
    func fetchTasks(employeeId: String) async throws -> [WorkTask] {
        // For employees, we need to query across all locations
        // This is a limitation of subcollections - we'll need to search
        // For now, return empty array - this would need a different approach
        // or we could store employeeId in the user document and query from there
        return []
    }
    
    func createTask(userId: String, locationId: String, task: WorkTask) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task)
    }
    
    func updateTask(userId: String, locationId: String, task: WorkTask) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task, merge: true)
    }
    
    func deleteTask(userId: String, locationId: String, taskId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .document(taskId)
            .delete()
    }
    
    func observeTasks(userId: String, locationId: String, completion: @escaping ([WorkTask]) -> Void) {
        let listener = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let tasks = documents.compactMap { doc in
                    try? doc.data(as: WorkTask.self)
                }
                // Ensure callback runs on main thread
                Task { @MainActor in
                    completion(tasks)
                }
            }
        listeners["tasks_\(userId)_\(locationId)"] = listener
    }
    
    func observeEmployeeTasks(employeeId: String, completion: @escaping ([WorkTask]) -> Void) {
        // Note: This is complex with subcollections. For now, return empty
        // In production, you'd need to query across all user locations
        completion([])
    }
    
    // MARK: - Shifts (as subcollection under locations)
    
    func fetchShifts(userId: String, locationId: String) async throws -> [Shift] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .getDocuments()
        let shifts = try snapshot.documents.compactMap { doc in
            try doc.data(as: Shift.self)
        }
        // Sort: active shifts first, then assigned, then completed (by clockOutTime desc)
        return shifts.sorted { shift1, shift2 in
            if shift1.isActive && !shift2.isActive { return true }
            if !shift1.isActive && shift2.isActive { return false }
            if shift1.isAssigned && !shift2.isAssigned { return true }
            if !shift1.isAssigned && shift2.isAssigned { return false }
            // For completed shifts, sort by clockOutTime descending
            if let out1 = shift1.clockOutTime, let out2 = shift2.clockOutTime {
                return out1 > out2
            }
            return false
        }
    }
    
    func fetchShifts(employeeId: String) async throws -> [Shift] {
        // Similar limitation as tasks - would need to query across locations
        return []
    }
    
    func createShift(userId: String, locationId: String, shift: Shift) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .document(shift.id)
            .setData(from: shift)
    }
    
    func updateShift(userId: String, locationId: String, shift: Shift) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .document(shift.id)
            .setData(from: shift, merge: true)
    }
    
    func deleteShift(userId: String, locationId: String, shiftId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .document(shiftId)
            .delete()
    }
    
    func observeShifts(userId: String, locationId: String, employeeId: String, completion: @escaping ([Shift]) -> Void) {
        let listener = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .whereField("employeeId", isEqualTo: employeeId)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let shifts = documents.compactMap { doc in
                    try? doc.data(as: Shift.self)
                }
                // Sort: active shifts first, then assigned, then completed
                let sorted = shifts.sorted { shift1, shift2 in
                    if shift1.isActive && !shift2.isActive { return true }
                    if !shift1.isActive && shift2.isActive { return false }
                    if shift1.isAssigned && !shift2.isAssigned { return true }
                    if !shift1.isAssigned && shift2.isAssigned { return false }
                    if let out1 = shift1.clockOutTime, let out2 = shift2.clockOutTime {
                        return out1 > out2
                    }
                    return false
                }
                completion(sorted)
            }
        listeners["shifts_\(userId)_\(locationId)_\(employeeId)"] = listener
    }
    
    // MARK: - Lottery Forms (as subcollection under locations)
    
    func fetchLotteryForms(userId: String, locationId: String) async throws -> [LotteryForm] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .order(by: "submittedAt", descending: true)
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: LotteryForm.self)
        }
    }
    
    func fetchLotteryForms(shiftId: String) async throws -> [LotteryForm] {
        // Similar limitation - would need to query across locations
        return []
    }
    
    func createLotteryForm(userId: String, locationId: String, form: LotteryForm) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .document(form.id)
            .setData(from: form)
    }
    
    func observeLotteryForms(userId: String, locationId: String, completion: @escaping ([LotteryForm]) -> Void) {
        let listener = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .order(by: "submittedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let forms = documents.compactMap { doc in
                    try? doc.data(as: LotteryForm.self)
                }
                completion(forms)
            }
        listeners["lottery_\(userId)_\(locationId)"] = listener
    }
    
    // MARK: - Lottery Form Template
    
    func saveLotteryFormTemplate(userId: String, locationId: String, template: LotteryFormTemplate) async throws {
        var updatedTemplate = template
        updatedTemplate = LotteryFormTemplate(locationId: locationId, rows: template.rows, lastUpdated: Date())
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryFormTemplate")
            .document("template")
            .setData(from: updatedTemplate)
    }
    
    func fetchLotteryFormTemplate(userId: String, locationId: String) async throws -> LotteryFormTemplate? {
        let document = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryFormTemplate")
            .document("template")
            .getDocument()
        
        guard document.exists else {
            return nil
        }
        
        return try document.data(as: LotteryFormTemplate.self)
    }
    
    // MARK: - Firebase Storage
    
    func uploadTaskImage(imageData: Data, taskId: String, userId: String, locationId: String) async throws -> String {
        let storage = Storage.storage()
        let imageRef = storage.reference().child("task_images/\(userId)/\(locationId)/\(taskId).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            _ = imageRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                imageRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                    }
                }
            }
        }
    }
    
    // MARK: - Documents (as subcollection under locations)
    
    func fetchDocuments(userId: String, locationId: String) async throws -> [Document] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("documents")
            .order(by: "uploadedAt", descending: true)
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Document.self)
        }
    }
    
    func createDocument(userId: String, locationId: String, document: Document) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("documents")
            .document(document.id)
            .setData(from: document)
    }
    
    func deleteDocument(userId: String, locationId: String, documentId: String) async throws {
        // First, get the document to get the file URL
        let docRef = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("documents")
            .document(documentId)
        
        let document = try await docRef.getDocument()
        if let documentData = try? document.data(as: Document.self) {
            // Delete from Firebase Storage
            let storage = Storage.storage()
            let fileRef = storage.reference(forURL: documentData.fileURL)
            try? await fileRef.delete()
        }
        
        // Delete from Firestore
        try await docRef.delete()
    }
    
    func uploadDocument(fileData: Data, fileName: String, fileType: String, userId: String, locationId: String) async throws -> String {
        let storage = Storage.storage()
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let sanitizedFileName = fileName.replacingOccurrences(of: " ", with: "_")
        let documentRef = storage.reference().child("documents/\(userId)/\(locationId)/\(sanitizedFileName)")
        
        let metadata = StorageMetadata()
        
        // Set content type based on file type
        switch fileExtension {
        case "pdf":
            metadata.contentType = "application/pdf"
        case "jpg", "jpeg":
            metadata.contentType = "image/jpeg"
        case "png":
            metadata.contentType = "image/png"
        case "doc", "docx":
            metadata.contentType = "application/msword"
        default:
            metadata.contentType = "application/octet-stream"
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            _ = documentRef.putData(fileData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                documentRef.downloadURL { url, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"]))
                    }
                }
            }
        }
    }
    
    // Fetch all documents across all locations for a manager (for notifications)
    func fetchAllDocuments(userId: String) async throws -> [Document] {
        let locations = try await fetchLocations(userId: userId)
        var allDocuments: [Document] = []
        
        for location in locations {
            do {
                let documents = try await fetchDocuments(userId: userId, locationId: location.id)
                allDocuments.append(contentsOf: documents)
            } catch {
                // Continue with other locations if one fails
                continue
            }
        }
        
        return allDocuments
    }
    
    // MARK: - Cleanup
    
    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
}
