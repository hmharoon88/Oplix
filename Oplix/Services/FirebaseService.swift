//
//  FirebaseService.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    
    // Static cache to prevent fetching same user multiple times
    private static var userCache: [String: (user: User, timestamp: Date)] = [:]
    private static var cacheLock = NSLock()
    private static let cacheExpiration: TimeInterval = 60 // Cache for 60 seconds
    private static var fetchInProgress: Set<String> = [] // Track which users are being fetched
    
    // Helper function for async-safe cache access
    private static func withCacheLock<T>(_ operation: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return operation()
    }
    
    private init() {}
    
    /// Secondary Firebase app used only to provision employee/supervisor Auth accounts
    /// without replacing the manager's primary `Auth.auth()` session.
    private static let secondaryAuthAppName = "OplixEmployeeProvisioning"
    
    private func authForProvisioningStaffAccount() throws -> Auth {
        if let app = FirebaseApp.app(name: Self.secondaryAuthAppName) {
            return Auth.auth(app: app)
        }
        guard let primaryApp = FirebaseApp.app() else {
            throw NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured"]
            )
        }
        FirebaseApp.configure(name: Self.secondaryAuthAppName, options: primaryApp.options)
        guard let secondaryApp = FirebaseApp.app(name: Self.secondaryAuthAppName) else {
            throw NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to configure secondary Firebase app"]
            )
        }
        return Auth.auth(app: secondaryApp)
    }
    
    private static func shouldProvisionStaffOnSecondaryAuth(role: User.UserRole) -> Bool {
        role != .manager && Auth.auth().currentUser != nil
    }
    
    // MARK: - Authentication
    
    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        
        // Fetch user to check their role
        do {
            let user = try await fetchUser(userId: result.user.uid)
            
            // Require email verification for managers only
            if user.role == .manager {
                guard result.user.isEmailVerified else {
                    // Sign out and throw error
                    try Auth.auth().signOut()
                    throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please verify your email before signing in. Check your inbox for the verification link."])
                }
            }
            
            return user
        } catch {
            // If user document doesn't exist, sign out and throw a clearer error
            try? Auth.auth().signOut()
            if let nsError = error as NSError?, nsError.domain == "FirebaseFirestore" {
                throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User account not found. Please contact your manager."])
            }
            throw error
        }
    }
    
    func signOut() throws {
        // Remove all listeners before signing out
        removeAllListeners()
        try Auth.auth().signOut()
    }
    
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
    
    func resendEmailVerification(email: String, password: String) async throws {
        // Sign in temporarily to get the user
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        
        // Check if already verified
        if result.user.isEmailVerified {
            try Auth.auth().signOut()
            throw NSError(domain: "FirebaseService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Email is already verified. You can sign in now."])
        }
        
        // Resend verification email
        try await result.user.sendEmailVerification()
        
        // Sign out again
        try Auth.auth().signOut()
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
    
    func createUser(email: String, password: String, username: String, role: User.UserRole, locationId: String?, managerUserId: String? = nil, signOutAfterCreation: Bool = true, managerEmail: String? = nil, managerPassword: String? = nil) async throws -> User {
        if Self.shouldProvisionStaffOnSecondaryAuth(role: role) {
            let secondaryAuth = try authForProvisioningStaffAccount()
            let result = try await secondaryAuth.createUser(withEmail: email, password: password)
            defer { try? secondaryAuth.signOut() }
            
            let user = User(
                id: result.user.uid,
                username: username,
                role: role,
                locationId: locationId,
                managerUserId: managerUserId,
                createdAt: Date()
            )
            
            do {
                try db.collection("users").document(user.id).setData(from: user)
                print("✅ User document created (secondary auth) for \(user.id) with role \(user.role.rawValue)")
            } catch {
                print("🔴 Error creating User document: \(error.localizedDescription)")
                throw error
            }
            
            return user
        }
        
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        if role == .manager {
            do {
                try await result.user.sendEmailVerification()
            } catch {
                print("⚠️ Warning: Failed to send verification email: \(error.localizedDescription)")
            }
        }
        
        let user = User(
            id: result.user.uid,
            username: username,
            role: role,
            locationId: locationId,
            managerUserId: managerUserId,
            createdAt: Date()
        )
        
        do {
            try db.collection("users").document(user.id).setData(from: user)
            print("✅ User document created successfully for \(user.id) with role \(user.role.rawValue)")
        } catch {
            print("🔴 Error creating User document: \(error.localizedDescription)")
            throw error
        }
        
        if signOutAfterCreation {
            try Auth.auth().signOut()
        }
        
        return user
    }
    
    func fetchUser(userId: String) async throws -> User {
        // Check cache first
        let cachedUser: User? = FirebaseService.withCacheLock {
            if let cached = FirebaseService.userCache[userId] {
                let age = Date().timeIntervalSince(cached.timestamp)
                if age < FirebaseService.cacheExpiration {
                    // Don't print cache hits to reduce log spam
                    return cached.user
                } else {
                    // Cache expired, remove it
                    FirebaseService.userCache.removeValue(forKey: userId)
                }
            }
            return nil
        }
        
        if let cached = cachedUser {
            return cached
        }
        
        // Check if already being fetched
        let isInProgress = FirebaseService.withCacheLock {
            return FirebaseService.fetchInProgress.contains(userId)
        }
        
        if isInProgress {
            // Wait a bit and check cache again (another call might have finished)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            let retryCached: User? = FirebaseService.withCacheLock {
                if let cached = FirebaseService.userCache[userId] {
                    let age = Date().timeIntervalSince(cached.timestamp)
                    if age < FirebaseService.cacheExpiration {
                        return cached.user
                    }
                }
                return nil
            }
            if let retryCached = retryCached {
                return retryCached
            }
        }
        
        // Mark as in progress
        _ = FirebaseService.withCacheLock {
            FirebaseService.fetchInProgress.insert(userId)
        }
        
        defer {
            // Remove from in-progress set when done
            _ = FirebaseService.withCacheLock {
                FirebaseService.fetchInProgress.remove(userId)
            }
        }
        
        // Not in cache or expired, fetch from Firestore
        print("🔵 fetchUser called for userId: \(userId) (not in cache)")
        let document = try await db.collection("users").document(userId).getDocument()
        
        guard document.exists else {
            print("🔴 User document does not exist for userId: \(userId)")
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User account not found. Please contact your manager."])
        }
        
        do {
            let user = try document.data(as: User.self)
            
            // Cache the user
            FirebaseService.withCacheLock {
                FirebaseService.userCache[userId] = (user: user, timestamp: Date())
            }
            
            print("✅ User fetched successfully: \(user.id), role: \(user.role.rawValue)")
            return user
        } catch {
            print("🔴 Error decoding User document: \(error.localizedDescription)")
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User account data is invalid. Please contact your manager."])
        }
    }
    
    func updateUser(userId: String, user: User) async throws {
        try db.collection("users").document(userId).setData(from: user, merge: true)
    }

    /// Update only the `role` field on a User document. Used by the
    /// master Employees editor to promote/demote between
    /// `.employee` and `.supervisor` without touching other User fields
    /// (which include immutable `let` properties like `username` and
    /// `id`). Uses `updateData` rather than re-encoding the whole doc so
    /// we don't risk overwriting fields with stale values.
    func updateUserRole(userId: String, role: User.UserRole) async throws {
        try await db.collection("users").document(userId).updateData([
            "role": role.rawValue
        ])
    }

    /// Update only the `notificationPrefs` map on a User document.
    /// We deliberately encode just this one field (rather than calling
    /// `updateUser(user:)` with the whole struct) so the write touches
    /// nothing else — that keeps it safe against races where the local
    /// `User` copy might be slightly stale, and ensures we never alter
    /// existing user data when a user just toggles a notification.
    func updateNotificationPrefs(userId: String, prefs: NotificationPrefs) async throws {
        // Encode the prefs struct into a Firestore-friendly dictionary
        // via JSON round-trip. This honours the optional/`nil` fields
        // so unchecked toggles don't get persisted as `false` — they
        // simply remain absent and resolve to their defaults later.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(prefs)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "FirebaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode notification prefs"]
            )
        }
        try await db.collection("users").document(userId).updateData([
            "notificationPrefs": dict
        ])
    }

    /// Record that the user acknowledged a Needs Attention alert so it
    /// stays hidden on Home and Location screens across devices.
    func acknowledgeAlert(userId: String, alertId: String) async throws {
        try await db.collection("users").document(userId).updateData([
            "acknowledgedAlertIds": FieldValue.arrayUnion([alertId])
        ])
        FirebaseService.withCacheLock {
            if let cached = FirebaseService.userCache[userId] {
                var user = cached.user
                if !user.resolvedAcknowledgedAlertIds.contains(alertId) {
                    var ids = user.resolvedAcknowledgedAlertIds
                    ids.append(alertId)
                    user.acknowledgedAlertIds = ids
                }
                FirebaseService.userCache[userId] = (user: user, timestamp: Date())
            }
        }
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
        guard Auth.auth().currentUser?.uid != nil else { return nil }
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
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(location.id)
            .setData(from: location)
    }
    
    func updateLocation(userId: String, location: Location) async throws {
        try db.collection("users")
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

    /// Fetch a single manager-level employee record. Faster than pulling
    /// the entire `fetchManagerEmployees` list when the caller only needs
    /// one record (e.g. the location-picker shell resolving the active
    /// user's `assignedLocationIds`).
    func fetchManagerEmployee(userId: String, employeeId: String) async throws -> Employee {
        let document = try await db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employeeId)
            .getDocument()
        return try document.data(as: Employee.self)
    }
    
    func createManagerEmployee(userId: String, employee: Employee) async throws {
        try db.collection("users")
            .document(userId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee)
    }
    
    func updateManagerEmployee(userId: String, employee: Employee) async throws {
        try db.collection("users")
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
            try db.collection("users").document(employeeId).setData(from: user, merge: true)
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
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("employees")
            .document(employee.id)
            .setData(from: employee)
    }
    
    func updateEmployee(userId: String, locationId: String, employee: Employee) async throws {
        try db.collection("users")
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
        try db.collection("users")
            .document(userId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task)
    }
    
    func updateManagerTask(userId: String, task: WorkTask) async throws {
        try db.collection("users")
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
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("tasks")
            .document(task.id)
            .setData(from: task)
    }
    
    func updateTask(userId: String, locationId: String, task: WorkTask) async throws {
        try db.collection("users")
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

    // Observe the manager-level task mirror (used by dashboard score bars).
    // Fires whenever any task changes — completions, edits, adds, deletes.
    func observeManagerTasks(userId: String, completion: @escaping ([WorkTask]) -> Void) {
        let listener = db.collection("users")
            .document(userId)
            .collection("tasks")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                let tasks = documents.compactMap { doc in
                    try? doc.data(as: WorkTask.self)
                }
                Task { @MainActor in
                    completion(tasks)
                }
            }
        listeners["managerTasks_\(userId)"] = listener
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
    
    // Fetch all shifts across all locations for a manager
    func fetchAllShifts(userId: String) async throws -> [Shift] {
        let locations = try await fetchLocations(userId: userId)
        var allShifts: [Shift] = []
        
        for location in locations {
            do {
                let shifts = try await fetchShifts(userId: userId, locationId: location.id)
                allShifts.append(contentsOf: shifts)
            } catch {
                // Continue with other locations if one fails
                continue
            }
        }
        
        // Sort: active shifts first, then assigned, then completed (by clockOutTime desc)
        return allShifts.sorted { shift1, shift2 in
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
    
    func createShift(userId: String, locationId: String, shift: Shift) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("shifts")
            .document(shift.id)
            .setData(from: shift)
    }
    
    func updateShift(userId: String, locationId: String, shift: Shift) async throws {
        try db.collection("users")
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
    
    // MARK: - Announcements
    //
    // Path: users/{managerUserId}/announcements/{announcementId}
    // Doc shape mirrors `Announcement` in Models/Announcement.swift.
    // Written by the `sendAnnouncement` Cloud Function (server-side);
    // the client only reads + flips per-user `readBy` entries.

    /// Fetch all announcements owned by the given manager. Sorted
    /// newest-first. Filter to a specific recipient client-side if you
    /// want only what a single employee should see.
    func fetchAnnouncements(managerUserId: String) async throws -> [Announcement] {
        let snapshot = try await db.collection("users")
            .document(managerUserId)
            .collection("announcements")
            .order(by: "sentAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            // Older docs (before the inbox feature) may not have
            // `readBy` — that's fine, defaults to nil → "unread for
            // everyone." Decode manually so we can be tolerant of
            // missing fields without throwing.
            guard let title = data["title"] as? String,
                  let body = data["body"] as? String,
                  let authorId = data["authorId"] as? String,
                  let recipientIds = data["recipientIds"] as? [String] else {
                print("⚠️ Skipping malformed announcement \(doc.documentID)")
                return nil
            }
            let sentAt: Date
            if let ts = data["sentAt"] as? Timestamp {
                sentAt = ts.dateValue()
            } else if let d = data["sentAt"] as? Date {
                sentAt = d
            } else {
                sentAt = Date()
            }
            let locationId = data["locationId"] as? String
            // Firestore returns the `readBy` map as `[String: Timestamp]`.
            var readBy: [String: Date]? = nil
            if let raw = data["readBy"] as? [String: Timestamp] {
                readBy = raw.mapValues { $0.dateValue() }
            }
            return Announcement(
                id: doc.documentID,
                title: title,
                body: body,
                locationId: locationId,
                authorId: authorId,
                recipientIds: recipientIds,
                sentAt: sentAt,
                readBy: readBy
            )
        }
    }

    /// Live observer for announcements owned by the given manager.
    /// Returns a listener registration so the caller can detach when
    /// the view goes away.
    @discardableResult
    func observeAnnouncements(
        managerUserId: String,
        onChange: @escaping ([Announcement]) -> Void
    ) -> ListenerRegistration {
        return db.collection("users")
            .document(managerUserId)
            .collection("announcements")
            .order(by: "sentAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("⚠️ Announcements observer error: \(error.localizedDescription)")
                    return
                }
                guard let snapshot = snapshot else { return }
                let announcements: [Announcement] = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    guard let title = data["title"] as? String,
                          let body = data["body"] as? String,
                          let authorId = data["authorId"] as? String,
                          let recipientIds = data["recipientIds"] as? [String] else {
                        return nil
                    }
                    let sentAt: Date = (data["sentAt"] as? Timestamp)?.dateValue()
                        ?? (data["sentAt"] as? Date)
                        ?? Date()
                    let locationId = data["locationId"] as? String
                    var readBy: [String: Date]? = nil
                    if let raw = data["readBy"] as? [String: Timestamp] {
                        readBy = raw.mapValues { $0.dateValue() }
                    }
                    return Announcement(
                        id: doc.documentID,
                        title: title,
                        body: body,
                        locationId: locationId,
                        authorId: authorId,
                        recipientIds: recipientIds,
                        sentAt: sentAt,
                        readBy: readBy
                    )
                }
                onChange(announcements)
            }
    }

    /// Mark a single announcement as read for the given user. Uses a
    /// nested merge write so we never clobber other recipients'
    /// timestamps. No-op if the user is already in `readBy`.
    func markAnnouncementRead(
        managerUserId: String,
        announcementId: String,
        userId: String
    ) async throws {
        try await db.collection("users")
            .document(managerUserId)
            .collection("announcements")
            .document(announcementId)
            .setData([
                "readBy": [userId: FieldValue.serverTimestamp()]
            ], merge: true)
    }

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

    /// Most recent closes for a location, newest first. Used by the
    /// duplicate-close guard and the Begin verification at shift close.
    /// Pass `source: .server` to bypass the offline cache — that makes
    /// the call double as the "are we really online?" check.
    func fetchRecentLotteryForms(
        userId: String,
        locationId: String,
        limit: Int,
        source: FirestoreSource = .default
    ) async throws -> [LotteryForm] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .order(by: "submittedAt", descending: true)
            .limit(to: limit)
            .getDocuments(source: source)
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: LotteryForm.self)
        }
    }
    
    func createLotteryForm(userId: String, locationId: String, form: LotteryForm) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .document(form.id)
            .setData(from: form)
    }
    
    func updateLotteryFormOverShort(userId: String, locationId: String, formId: String, overShort: Double) async throws {
        // Fetch the existing form
        let formRef = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryForms")
            .document(formId)
        
        let document = try await formRef.getDocument()
        guard document.exists else {
            throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lottery form not found"])
        }
        
        // Decode the existing form
        var form = try document.data(as: LotteryForm.self)
        
        // Update the overShort in shiftSummary
        if var summary = form.shiftSummary {
            // Create a new summary with updated overShort
            // Since ShiftSummaryData is a struct with let properties, we need to create a new one
            form.shiftSummary = ShiftSummaryData(
                totalSold: summary.totalSold,
                totalDollars: summary.totalDollars,
                totalBooks: summary.totalBooks,
                instantTotal: summary.instantTotal,
                onlineTotal: summary.onlineTotal,
                totalSoldAmount: summary.totalSoldAmount,
                registerCash: summary.registerCash,
                totalCash: summary.totalCash,
                onlineCashes: summary.onlineCashes,
                instantCashes: summary.instantCashes,
                totalCashes: summary.totalCashes,
                cashInBag: summary.cashInBag,
                cashInBagNet: summary.cashInBagNet,
                overShort: overShort,
                lotteryReturnDeduction: summary.lotteryReturnDeduction,
                lotteryPackCloseoutAddition: summary.lotteryPackCloseoutAddition,
                packReturns: summary.packReturns
            )
        }
        
        // Save the updated form
        try formRef.setData(from: form, merge: false)
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
    
    /// Doc id used in the `lotteryFormTemplate` subcollection for a
    /// given terminal. Terminal 1 — including the implicit/legacy
    /// single-terminal case where `terminalNumber == nil` — keeps the
    /// existing `"template"` doc id so we don't have to migrate a
    /// single byte of existing data. Higher-numbered terminals use
    /// `"terminal_2"`, `"terminal_3"`, …
    private func lotteryTemplateDocId(for terminalNumber: Int?) -> String {
        let n = terminalNumber ?? 1
        return n <= 1 ? "template" : "terminal_\(n)"
    }

    func saveLotteryFormTemplate(userId: String, locationId: String, template: LotteryFormTemplate) async throws {
        // Persist a fresh `lastUpdated`. We deliberately preserve the
        // caller's `terminalNumber` (and treat nil as terminal 1) so
        // single-terminal callers don't have to learn about terminals.
        let updatedTemplate = LotteryFormTemplate(
            locationId: locationId,
            rows: template.rows,
            lastUpdated: Date(),
            lotteryRegisterAmount: template.lotteryRegisterAmount,
            reverseOrder: template.reverseOrder,
            terminalNumber: template.terminalNumber
        )

        let docId = lotteryTemplateDocId(for: template.terminalNumber)
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryFormTemplate")
            .document(docId)
            .setData(from: updatedTemplate)
    }

    /// Single-terminal / legacy fetch. Reads doc id `"template"` and
    /// returns it unchanged. Used by the existing single-terminal code
    /// paths so they don't have to know terminals exist.
    func fetchLotteryFormTemplate(userId: String, locationId: String) async throws -> LotteryFormTemplate? {
        return try await fetchLotteryFormTemplate(userId: userId, locationId: locationId, terminalNumber: nil)
    }

    /// Terminal-aware fetch. `nil` (or `1`) reads the legacy `"template"`
    /// doc; higher numbers read `"terminal_N"`. Returns nil if the doc
    /// is absent (e.g. terminal 3 was never configured).
    /// Pass `source: .server` to bypass the offline cache (required at
    /// shift close, where a cached copy can silently be hours old).
    func fetchLotteryFormTemplate(
        userId: String,
        locationId: String,
        terminalNumber: Int?,
        source: FirestoreSource = .default
    ) async throws -> LotteryFormTemplate? {
        let docId = lotteryTemplateDocId(for: terminalNumber)
        let document = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryFormTemplate")
            .document(docId)
            .getDocument(source: source)

        guard document.exists else { return nil }
        return try document.data(as: LotteryFormTemplate.self)
    }

    /// Fetch every template doc under `lotteryFormTemplate/`. Returns
    /// them sorted by `effectiveTerminalNumber`. Used by the
    /// multi-terminal customization UI to render one tab per terminal.
    func fetchAllLotteryFormTemplates(
        userId: String,
        locationId: String
    ) async throws -> [LotteryFormTemplate] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryFormTemplate")
            .getDocuments()

        let templates: [LotteryFormTemplate] = snapshot.documents.compactMap { doc in
            try? doc.data(as: LotteryFormTemplate.self)
        }

        return templates.sorted {
            $0.effectiveTerminalNumber < $1.effectiveTerminalNumber
        }
    }

    // MARK: - Lottery Returns

    func fetchPendingLotteryReturns(
        userId: String,
        locationId: String,
        terminalNumber: Int? = nil
    ) async throws -> [LotteryReturn] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryReturns")
            .whereField("status", isEqualTo: LotteryReturnStatus.pending.rawValue)
            .getDocuments()

        let all = try snapshot.documents.compactMap { doc -> LotteryReturn? in
            try doc.data(as: LotteryReturn.self)
        }

        guard let terminalNumber, terminalNumber > 1 else {
            return all.filter { ($0.terminalNumber ?? 1) <= 1 }
        }
        return all.filter { ($0.terminalNumber ?? 1) == terminalNumber }
    }

    /// Recent returns (pending + applied) for pack inventory history.
    func fetchRecentLotteryReturns(
        userId: String,
        locationId: String,
        terminalNumber: Int? = nil,
        limit: Int = 40
    ) async throws -> [LotteryReturn] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryReturns")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        let all = try snapshot.documents.compactMap { doc -> LotteryReturn? in
            try doc.data(as: LotteryReturn.self)
        }

        guard let terminalNumber, terminalNumber > 1 else {
            return all.filter { ($0.terminalNumber ?? 1) <= 1 }
        }
        return all.filter { ($0.terminalNumber ?? 1) == terminalNumber }
    }

    func createLotteryReturn(
        userId: String,
        locationId: String,
        lotteryReturn: LotteryReturn
    ) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryReturns")
            .document(lotteryReturn.id)
            .setData(from: lotteryReturn)
    }

    func markLotteryReturnsApplied(
        userId: String,
        locationId: String,
        returnIds: [String],
        shiftId: String
    ) async throws {
        guard !returnIds.isEmpty else { return }
        let batch = db.batch()
        let collection = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryReturns")

        for id in returnIds {
            let ref = collection.document(id)
            batch.updateData([
                "status": LotteryReturnStatus.applied.rawValue,
                "appliedAt": FieldValue.serverTimestamp(),
                "appliedShiftId": shiftId,
            ], forDocument: ref)
        }
        try await batch.commit()
    }

    // MARK: - Lottery Pack Closeouts (finished packs replaced mid-shift)

    func fetchPendingLotteryPackCloseouts(
        userId: String,
        locationId: String,
        terminalNumber: Int? = nil
    ) async throws -> [LotteryPackCloseout] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryPackCloseouts")
            .whereField("status", isEqualTo: LotteryPackCloseoutStatus.pending.rawValue)
            .getDocuments()

        let all = try snapshot.documents.compactMap { doc -> LotteryPackCloseout? in
            try doc.data(as: LotteryPackCloseout.self)
        }

        guard let terminalNumber, terminalNumber > 1 else {
            return all.filter { ($0.terminalNumber ?? 1) <= 1 }
        }
        return all.filter { ($0.terminalNumber ?? 1) == terminalNumber }
    }

    func createLotteryPackCloseout(
        userId: String,
        locationId: String,
        closeout: LotteryPackCloseout
    ) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryPackCloseouts")
            .document(closeout.id)
            .setData(from: closeout)
    }

    func markLotteryPackCloseoutsApplied(
        userId: String,
        locationId: String,
        closeoutIds: [String],
        shiftId: String
    ) async throws {
        guard !closeoutIds.isEmpty else { return }
        let batch = db.batch()
        let collection = db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryPackCloseouts")

        for id in closeoutIds {
            let ref = collection.document(id)
            batch.updateData([
                "status": LotteryPackCloseoutStatus.applied.rawValue,
                "appliedAt": FieldValue.serverTimestamp(),
                "appliedShiftId": shiftId,
            ], forDocument: ref)
        }
        try await batch.commit()
    }

    // MARK: - Lottery Stock (received packs not yet on a bin)

    func fetchInStockLotteryPacks(
        userId: String,
        locationId: String
    ) async throws -> [LotteryStockPack] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryStock")
            .whereField("status", isEqualTo: LotteryStockPackStatus.inStock.rawValue)
            .getDocuments()

        return try snapshot.documents.compactMap { doc -> LotteryStockPack? in
            try doc.data(as: LotteryStockPack.self)
        }
        .sorted { lhs, rhs in
            let gameCmp = lhs.gameNumber.localizedStandardCompare(rhs.gameNumber)
            if gameCmp != .orderedSame { return gameCmp == .orderedAscending }
            return lhs.packSerial.localizedStandardCompare(rhs.packSerial) == .orderedAscending
        }
    }

    func createLotteryStockPack(
        userId: String,
        locationId: String,
        pack: LotteryStockPack
    ) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryStock")
            .document(pack.id)
            .setData(from: pack)
    }

    func markLotteryStockPackAssigned(
        userId: String,
        locationId: String,
        packId: String,
        rowId: String,
        binNumber: String
    ) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("lotteryStock")
            .document(packId)
            .updateData([
                "status": LotteryStockPackStatus.assigned.rawValue,
                "assignedAt": FieldValue.serverTimestamp(),
                "assignedRowId": rowId,
                "assignedBinNumber": binNumber
            ])
    }

    func findInStockLotteryPack(
        userId: String,
        locationId: String,
        packSerial: String
    ) async throws -> LotteryStockPack? {
        let packs = try await fetchInStockLotteryPacks(userId: userId, locationId: locationId)
        return packs.first {
            OhioLotteryBarcodeParser.packSerialsMatch($0.packSerial, packSerial)
        }
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
    
    func uploadTaskImages(imageDataList: [Data], taskId: String, userId: String, locationId: String) async throws -> [String] {
        let storage = Storage.storage()
        var uploadedURLs: [String] = []
        
        // Upload all images in parallel
        try await withThrowingTaskGroup(of: String.self) { group in
            for imageData in imageDataList {
                group.addTask {
                    let imageId = UUID().uuidString
                    let imageRef = storage.reference().child("task_images/\(userId)/\(locationId)/\(taskId)/\(imageId).jpg")
                    
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
            }
            
            // Collect all uploaded URLs
            for try await url in group {
                uploadedURLs.append(url)
            }
        }
        
        return uploadedURLs
    }
    
    func uploadLotteryFormImage(imageData: Data, formId: String, userId: String, locationId: String) async throws -> String {
        let storage = Storage.storage()
        let imageRef = storage.reference().child("lottery_form_images/\(userId)/\(locationId)/\(formId).jpg")
        
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
        try db.collection("users")
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
    
    // MARK: - Global Game Database (accessible by all managers)
    
    func saveGameData(_ gameData: GameData) async throws {
        var updatedGameData = gameData
        updatedGameData = GameData(
            id: gameData.id,
            gameNumber: gameData.gameNumber,
            value: gameData.value,
            tickets: gameData.tickets,
            createdAt: gameData.createdAt,
            lastUpdated: Date()
        )
        // Store at global level: /gameDatabase/{gameData.id}
        try db.collection("gameDatabase")
            .document(gameData.id)
            .setData(from: updatedGameData)
    }
    
    func fetchAllGameData() async throws -> [GameData] {
        let snapshot = try await db.collection("gameDatabase")
            .order(by: "gameNumber")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: GameData.self)
        }
    }
    
    func fetchGameData(gameNumber: String) async throws -> GameData? {
        let snapshot = try await db.collection("gameDatabase")
            .whereField("gameNumber", isEqualTo: gameNumber)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            return nil
        }
        
        return try document.data(as: GameData.self)
    }
    
    func deleteGameData(gameDataId: String) async throws {
        try await db.collection("gameDatabase")
            .document(gameDataId)
            .delete()
    }
    
    // MARK: - Invoices
    
    func saveInvoice(userId: String, invoice: Invoice) async throws {
        try db.collection("users")
            .document(userId)
            .collection("invoices")
            .document(invoice.id)
            .setData(from: invoice)
    }
    
    func fetchInvoices(userId: String, locationId: String? = nil) async throws -> [Invoice] {
        let collectionRef = db.collection("users")
            .document(userId)
            .collection("invoices")
        
        let snapshot: QuerySnapshot
        if let locationId = locationId {
            snapshot = try await collectionRef
                .whereField("locationId", isEqualTo: locationId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
        } else {
            snapshot = try await collectionRef
                .order(by: "createdAt", descending: true)
                .getDocuments()
        }
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Invoice.self)
        }
    }
    
    func updateInvoice(userId: String, invoice: Invoice) async throws {
        try db.collection("users")
            .document(userId)
            .collection("invoices")
            .document(invoice.id)
            .setData(from: invoice, merge: true)
    }
    
    func deleteInvoice(userId: String, invoiceId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("invoices")
            .document(invoiceId)
            .delete()
    }
    
    func uploadInvoiceFile(fileData: Data, invoiceId: String, userId: String, fileType: String, fileName: String) async throws -> String {
        let storage = Storage.storage()
        let fileExtension = fileType.lowercased()
        let fileRef = storage.reference().child("invoice_files/\(userId)/\(invoiceId).\(fileExtension)")
        
        let metadata = StorageMetadata()
        
        // Set content type based on file type
        switch fileExtension {
        case "pdf":
            metadata.contentType = "application/pdf"
        case "jpg", "jpeg":
            metadata.contentType = "image/jpeg"
        case "png":
            metadata.contentType = "image/png"
        case "xlsx":
            metadata.contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls":
            metadata.contentType = "application/vnd.ms-excel"
        case "doc", "docx":
            metadata.contentType = "application/msword"
        default:
            metadata.contentType = "application/octet-stream"
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            _ = fileRef.putData(fileData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                fileRef.downloadURL { url, error in
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
    
    // MARK: - Payables & Receivables
    
    func savePayable(userId: String, locationId: String, payable: Payable) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("payables")
            .document(payable.id)
            .setData(from: payable)
    }
    
    func fetchPayables(userId: String, locationId: String) async throws -> [Payable] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("payables")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Payable.self)
        }
    }
    
    func updatePayable(userId: String, locationId: String, payable: Payable) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("payables")
            .document(payable.id)
            .setData(from: payable, merge: true)
    }
    
    func deletePayable(userId: String, locationId: String, payableId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("payables")
            .document(payableId)
            .delete()
    }
    
    func saveReceivable(userId: String, locationId: String, receivable: Receivable) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("receivables")
            .document(receivable.id)
            .setData(from: receivable)
    }
    
    func fetchReceivables(userId: String, locationId: String) async throws -> [Receivable] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("receivables")
            .getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Receivable.self)
        }
    }
    
    func updateReceivable(userId: String, locationId: String, receivable: Receivable) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("receivables")
            .document(receivable.id)
            .setData(from: receivable, merge: true)
    }
    
    func deleteReceivable(userId: String, locationId: String, receivableId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("receivables")
            .document(receivableId)
            .delete()
    }

    // MARK: - Location reminders

    func fetchLocationReminders(userId: String, locationId: String) async throws -> [LocationReminder] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("reminders")
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: LocationReminder.self) }
    }

    func saveLocationReminder(userId: String, locationId: String, reminder: LocationReminder) async throws {
        try db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("reminders")
            .document(reminder.id)
            .setData(from: reminder, merge: true)
    }

    func deleteLocationReminder(userId: String, locationId: String, reminderId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("locations")
            .document(locationId)
            .collection("reminders")
            .document(reminderId)
            .delete()
    }

    // MARK: - Organization to-dos (manager home — synced with web)

    func observeOrgTodos(userId: String, completion: @escaping ([OrgTodo]) -> Void) {
        let key = "orgTodos_\(userId)"
        listeners[key]?.remove()
        let listener = db.collection("users")
            .document(userId)
            .collection("orgTodos")
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("⚠️ Org todos observer error: \(error.localizedDescription)")
                    return
                }
                let items = (snapshot?.documents ?? []).compactMap { OrgTodo.from(document: $0) }
                completion(items)
            }
        listeners[key] = listener
    }

    func removeOrgTodosListener(userId: String) {
        let key = "orgTodos_\(userId)"
        listeners[key]?.remove()
        listeners.removeValue(forKey: key)
    }

    /// Writes the same field shapes as `docs/js/org-todos-store.js` so web + app stay in sync.
    func saveOrgTodo(userId: String, todo: OrgTodo, isNew: Bool) async throws {
        var data: [String: Any] = [
            "title": todo.title,
            "notes": todo.notes,
            "dueDate": todo.dueDate,
            "isCompleted": todo.isCompleted,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if todo.isCompleted, let completedAt = todo.completedAt {
            data["completedAt"] = Self.orgTodoISO8601.string(from: completedAt)
        } else {
            data["completedAt"] = NSNull()
        }
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        try await db.collection("users")
            .document(userId)
            .collection("orgTodos")
            .document(todo.id)
            .setData(data, merge: true)
    }

    func deleteOrgTodo(userId: String, todoId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("orgTodos")
            .document(todoId)
            .delete()
    }

    private static let orgTodoISO8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Cleanup
    
    func removeAllListeners() {
        print("🟢 Removing all Firestore listeners...")
        for (key, listener) in listeners {
            listener.remove()
            print("🟢 Removed listener: \(key)")
        }
        listeners.removeAll()
        print("🟢 All listeners removed - count: \(listeners.count)")
    }
}
