//
//  ManagerEmployeesViewModel.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

@MainActor
class ManagerEmployeesViewModel: ObservableObject {
    @Published var employees: [Employee] = []
    @Published var locations: [Location] = []
    // Manager-wide tasks across all locations. Used to compute today's
    // task-completion badge on each employee row.
    @Published var tasks: [WorkTask] = []
    /// Resolved role for each employee, keyed by employee id. Populated on
    /// load by reading each employee's matching User document. Used by the
    /// edit screen to decide whether to surface supervisor-only permission
    /// toggles (canManageTasks, canEditSchedules, canManageDocuments, etc.).
    @Published var userRoles: [String: User.UserRole] = [:]
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
            async let employeesTask = firebaseService.fetchManagerEmployees(userId: userId)
            async let locationsTask = firebaseService.fetchLocations(userId: userId)
            async let tasksTask = firebaseService.fetchManagerTasks(userId: userId)
            
            employees = try await employeesTask
            locations = try await locationsTask
            // Tasks are non-critical for the screen — if they fail, we just
            // skip the progress badge rather than failing the whole screen.
            do {
                tasks = try await tasksTask
            } catch {
                tasks = []
            }

            // Resolve User.role for every employee in parallel so the edit
            // screen knows which ones to render supervisor-only toggles for.
            // Failures are silent (defaults to "employee") so this can never
            // block the list from rendering.
            await loadUserRoles(for: employees)
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Fetch User docs in parallel for the given employees and merge their
    /// roles into `userRoles`. Run as a non-throwing best-effort task — any
    /// missing role just defaults to `.employee` at read time via
    /// `role(for:)`.
    private func loadUserRoles(for employees: [Employee]) async {
        // Skip employees whose role we already resolved — covers the
        // refresh-after-edit case so we don't re-fetch the whole org each
        // time something tiny changes.
        let unresolved = employees.filter { userRoles[$0.id] == nil }
        guard !unresolved.isEmpty else { return }

        await withTaskGroup(of: (String, User.UserRole?).self) { group in
            for employee in unresolved {
                group.addTask { [firebaseService] in
                    let user = try? await firebaseService.fetchUser(userId: employee.id)
                    return (employee.id, user?.role)
                }
            }
            for await (id, role) in group {
                userRoles[id] = role ?? .employee
            }
        }
    }

    /// Convenience: returns the cached role for an employee, or `.employee`
    /// if we don't have a User doc on record. The supervisor-flag UI is
    /// gated on this — non-supervisors stay on the leaner permission set.
    func role(for employeeId: String) -> User.UserRole {
        userRoles[employeeId] ?? .employee
    }
    
    func createEmployee(name: String, password: String, workingHoursStart: String? = nil, workingHoursEnd: String? = nil, weeklySchedule: WeeklySchedule? = nil, is24Hours: Bool? = nil, assignedLocationIds: [String] = [], hourlyRate: Double? = nil, canTakeRegister: Bool = false, canSubmitLottery: Bool = false) async throws -> (username: String, email: String, password: String) {
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
                    locationId: assignedLocationIds.isEmpty ? nil : assignedLocationIds.first, // Use first assigned location as primary, or nil if unassigned
                    managerUserId: userId
                )
                break
            } catch {
                let nsError = error as NSError
                let isEmailExistsError = (nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17007) ||
                                       (error.localizedDescription.lowercased().contains("email") && error.localizedDescription.lowercased().contains("already"))
                
                if isEmailExistsError && attempts < maxAttempts - 1 {
                    let suffix = attempts + 1
                    finalUsername = "\(cleanBaseUsername)\(suffix)"
                    email = "\(finalUsername)@oplix.app"
                    attempts += 1
                    continue
                }
                throw error
            }
        }
        
        guard let createdUser = user else {
            throw NSError(domain: "ManagerEmployeesViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user after \(maxAttempts) attempts"])
        }
        
        // Create Employee document at manager level
        var employee = Employee(
            id: createdUser.id,
            name: name,
            username: finalUsername,
            locationId: assignedLocationIds.first,
            managerUserId: userId,
            password: password,
            shiftHistory: [],
            currentShiftStatus: .clockedOut,
            workingHoursStart: workingHoursStart,
            workingHoursEnd: workingHoursEnd,
            weeklySchedule: weeklySchedule,
            is24Hours: is24Hours,
            assignedLocationIds: assignedLocationIds,
            hourlyRate: hourlyRate
        )
        employee.canTakeRegister = canTakeRegister
        employee.canSubmitLottery = canSubmitLottery
        
        try await firebaseService.createManagerEmployee(userId: userId, employee: employee)
        
        // Assign to locations if any
        for locationId in assignedLocationIds {
            try await firebaseService.assignEmployeeToLocation(userId: userId, employeeId: employee.id, locationId: locationId)
        }
        
        await loadData()
        
        return (username: finalUsername, email: email, password: password)
    }
    
    func deleteEmployee(_ employee: Employee) async {
        do {
            // Unassign from all locations first
            for locationId in employee.assignedLocationIds {
                try? await firebaseService.unassignEmployeeFromLocation(userId: userId, employeeId: employee.id, locationId: locationId)
            }
            
            // Delete from manager collection
            try await firebaseService.deleteManagerEmployee(userId: userId, employeeId: employee.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete employee: \(error.localizedDescription)"
        }
    }
    
    func assignEmployeeToLocation(employeeId: String, locationId: String) async {
        do {
            try await firebaseService.assignEmployeeToLocation(userId: userId, employeeId: employeeId, locationId: locationId)
            await loadData()
        } catch {
            errorMessage = "Failed to assign employee: \(error.localizedDescription)"
        }
    }
    
    func unassignEmployeeFromLocation(employeeId: String, locationId: String) async {
        do {
            try await firebaseService.unassignEmployeeFromLocation(userId: userId, employeeId: employeeId, locationId: locationId)
            await loadData()
        } catch {
            errorMessage = "Failed to unassign employee: \(error.localizedDescription)"
        }
    }
    
    func updateEmployee(_ employee: Employee) async throws {
        // Update manager-level employee
        try await firebaseService.updateManagerEmployee(userId: userId, employee: employee)
        
        // Also update in all assigned location subcollections
        for locationId in employee.assignedLocationIds {
            var locationEmployee = employee
            locationEmployee.locationId = locationId // Set primary location for backward compatibility
            try await firebaseService.updateEmployee(userId: userId, locationId: locationId, employee: locationEmployee)
        }
        
        // Update User document if needed (username change)
        // Note: We'll need to add a method to FirebaseService to update User documents
        // For now, we'll skip this as username changes are less common
        
        await loadData()
    }
    
    /// Promote/demote an employee between `.employee` and `.supervisor`.
    /// Writes the new role to the User document and updates the local
    /// `userRoles` cache so any UI gated on `role(for:)` (the supervisor
    /// permissions section in the master editor) reacts immediately.
    /// Also forwards to `LocationDetailViewModel.setCachedRole` so the
    /// per-location screens bucket this person correctly the next time
    /// they load. The Employee record itself isn't touched here — the
    /// caller is responsible for clearing supervisor flags on demotion
    /// before saving the Employee, since those flags live on a different
    /// document.
    func updateUserRole(employeeId: String, newRole: User.UserRole) async throws {
        try await firebaseService.updateUserRole(userId: employeeId, role: newRole)
        userRoles[employeeId] = newRole
        LocationDetailViewModel.setCachedRole(newRole, for: employeeId)
    }

    func updateEmployeePassword(employeeId: String, newPassword: String) async throws {
        // Update password in manager-level employee
        guard var employee = employees.first(where: { $0.id == employeeId }) else {
            throw NSError(domain: "ManagerEmployeesViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Employee not found"])
        }
        
        employee.password = newPassword
        try await updateEmployee(employee)
    }
}

