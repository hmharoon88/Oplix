//
//  EditManagerEmployeeView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct EditManagerEmployeeView: View {
    @ObservedObject var viewModel: ManagerEmployeesViewModel
    @Environment(\.dismiss) var dismiss
    let employee: Employee
    
    @State private var name = ""
    @State private var password = ""
    @State private var locationSchedules: [String: WeeklySchedule] = [:] // Store schedule per location
    @State private var locationUseWeeklySchedule: [String: Bool] = [:] // Track if location uses weekly schedule
    @State private var locationHasWorkingHours: [String: Bool] = [:] // Track if location has working hours
    @State private var locationWorkingHoursStart: [String: Date] = [:] // Working hours start per location
    @State private var locationWorkingHoursEnd: [String: Date] = [:] // Working hours end per location
    @State private var hourlyRate = ""
    @State private var canTakeRegister = false
    @State private var canSubmitLottery = false
    @State private var is24Hours = false
    @State private var selectedLocationIds: Set<String> = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var scheduleConflicts: [String: [String]] = [:] // locationId: [conflicting location names]
    @State private var hasLoadedData = false // Prevent multiple loads

    // Password change (mirrors EmployeeDetailView UX so credentials work the
    // same way no matter which entry point you used to reach the editor).
    @State private var showingChangePassword = false
    /// When true, the password field uses plain text so the manager can read it.
    @State private var showPlaintextPassword = false

    // Supervisor-only permission toggles. Stored as plain Bool with a
    // separate "show" gate driven by `selectedRole`, so we never
    // accidentally write supervisor flags onto a regular employee record.
    @State private var canViewEmployeeData = false
    @State private var canManageTasks = false
    @State private var canManageDocuments = false
    @State private var canViewRegisterData = false
    @State private var canViewLotteryData = false
    @State private var canEditSchedules = false
    @State private var canViewReports = false

    // Role promotion / demotion. `selectedRole` is what's currently
    // visible in the picker and drives the supervisor section visibility.
    // `originalRole` is what was loaded from Firestore — we compare on
    // save to decide whether to issue a role write. `pendingRoleChange`
    // holds the picker target while the confirmation alert is showing
    // (so cancelling reverts cleanly).
    @State private var selectedRole: User.UserRole = .employee
    @State private var originalRole: User.UserRole = .employee
    @State private var pendingRoleChange: User.UserRole?
    @State private var showingRoleChangeAlert = false
    @State private var hasInitializedRole = false

    /// True when the employee being edited currently has the supervisor
    /// role in the picker. Drives whether the supervisor permissions
    /// section is rendered. Tied to `selectedRole` (not the saved
    /// Firestore value) so the section appears/disappears immediately
    /// when an admin toggles the picker, letting them configure flags
    /// in the same edit session before saving.
    private var isSupervisor: Bool {
        selectedRole == .supervisor
    }
    
    init(employee: Employee, viewModel: ManagerEmployeesViewModel) {
        print("🔵 EditManagerEmployeeView - INIT")
        print("   Employee ID: \(employee.id)")
        print("   Employee Name: \(employee.name)")
        print("   Assigned Locations: \(employee.assignedLocationIds)")
        print("   ViewModel locations count: \(viewModel.locations.count)")
        self.employee = employee
        _viewModel = ObservedObject(wrappedValue: viewModel)
        
        // Initialize state immediately to prevent re-renders
        _name = State(initialValue: employee.name)
        _password = State(initialValue: employee.password ?? "")
        _selectedLocationIds = State(initialValue: Set(employee.assignedLocationIds))
        _canTakeRegister = State(initialValue: employee.hasRegisterPermission)
        _canSubmitLottery = State(initialValue: employee.hasLotteryPermission)
        _is24Hours = State(initialValue: employee.is24Hours ?? false)

        // Supervisor-only permission flags. Stored on Employee but only
        // surfaced in the UI when we know this person's role is supervisor;
        // the helper still defaults nil → false so older records keep their
        // old behaviour.
        _canViewEmployeeData = State(initialValue: employee.canViewEmployeeData ?? false)
        _canManageTasks = State(initialValue: employee.canManageTasks ?? false)
        _canManageDocuments = State(initialValue: employee.canManageDocuments ?? false)
        _canViewRegisterData = State(initialValue: employee.canViewRegisterData ?? false)
        _canViewLotteryData = State(initialValue: employee.canViewLotteryData ?? false)
        _canEditSchedules = State(initialValue: employee.canEditSchedules ?? false)
        _canViewReports = State(initialValue: employee.canViewReports ?? false)
        
        if let rate = employee.hourlyRate {
            _hourlyRate = State(initialValue: String(format: "%.2f", rate))
        }
        
        // Initialize location schedules
        var schedules: [String: WeeklySchedule] = [:]
        var useWeekly: [String: Bool] = [:]
        var hasHours: [String: Bool] = [:]
        var startTimes: [String: Date] = [:]
        var endTimes: [String: Date] = [:]
        
        for locationId in employee.assignedLocationIds {
            if let schedule = employee.weeklySchedule {
                schedules[locationId] = schedule
                useWeekly[locationId] = true
            } else if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                hasHours[locationId] = true
                let components1 = startTime.split(separator: ":")
                let components2 = endTime.split(separator: ":")
                var dateComponents1 = DateComponents()
                var dateComponents2 = DateComponents()
                if components1.count == 2, let hour = Int(components1[0]), let minute = Int(components1[1]) {
                    dateComponents1.hour = hour
                    dateComponents1.minute = minute
                }
                if components2.count == 2, let hour = Int(components2[0]), let minute = Int(components2[1]) {
                    dateComponents2.hour = hour
                    dateComponents2.minute = minute
                }
                startTimes[locationId] = Calendar.current.date(from: dateComponents1) ?? Date()
                endTimes[locationId] = Calendar.current.date(from: dateComponents2) ?? Date()
                useWeekly[locationId] = false
            }
        }
        
        _locationSchedules = State(initialValue: schedules)
        _locationUseWeeklySchedule = State(initialValue: useWeekly)
        _locationHasWorkingHours = State(initialValue: hasHours)
        _locationWorkingHoursStart = State(initialValue: startTimes)
        _locationWorkingHoursEnd = State(initialValue: endTimes)
    }
    
    var body: some View {
        let _ = print("🔵 EditManagerEmployeeView - BODY RENDER")
        let _ = print("   Employee: \(employee.name) (ID: \(employee.id))")
        let _ = print("   Selected Locations: \(selectedLocationIds)")
        let _ = print("   ViewModel locations: \(viewModel.locations.count)")
        
        return ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            Form {
                scheduleConflictBannerSection
                employeeDetailsSection
                assignToLocationsSection
                scheduleSettingsSection
                compensationSection
                roleSection
                permissionsSection
                if isSupervisor {
                    supervisorPermissionsSection
                }
                loginCredentialsSection
            }
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(
                employeeName: employee.name,
                onSave: { newPassword in
                    password = newPassword
                    showingChangePassword = false
                },
                onCancel: { showingChangePassword = false }
            )
        }
        .navigationTitle("Edit Employee")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await updateEmployee()
                    }
                }
                .disabled(name.isEmpty || hasScheduleConflicts)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Employee updated successfully")
        }
        .alert(
            pendingRoleChange == .supervisor ? "Promote to Supervisor?" : "Demote to Employee?",
            isPresented: $showingRoleChangeAlert,
            presenting: pendingRoleChange
        ) { newRole in
            Button(newRole == .supervisor ? "Promote" : "Demote", role: .destructive) {
                // The picker is already at `newRole`. Just commit it as
                // the displayed selection so the supervisor section
                // visibility tracks. The actual Firestore write happens
                // in updateEmployee() on Save.
                selectedRole = newRole
                if newRole == .employee {
                    // Clean state on demote: clear all supervisor flags
                    // locally so when the Employee record is saved they
                    // get written back as false.
                    canViewEmployeeData = false
                    canManageTasks = false
                    canManageDocuments = false
                    canEditSchedules = false
                    canViewRegisterData = false
                    canViewLotteryData = false
                    canViewReports = false
                }
                pendingRoleChange = nil
            }
            Button("Cancel", role: .cancel) {
                // Revert the picker to the saved value. The onChange
                // observer's `newValue != originalRole` guard will
                // suppress the re-prompt this revert would otherwise
                // trigger.
                selectedRole = originalRole
                pendingRoleChange = nil
            }
        } message: { newRole in
            Text(newRole == .supervisor
                 ? "\(employee.name) will gain supervisor controls and access to the location's Task Check, Documents, Payables, and Receivables (per the toggles you'll set below). They must log out and back in for the change to take effect."
                 : "\(employee.name)'s supervisor controls will be removed and all supervisor permissions cleared. They must log out and back in for the change to take effect.")
        }
        .onChange(of: selectedRole) { _, newValue in
            // Only prompt when this is a real user-driven change (not the
            // initial load, and not a no-op on the currently-shown role).
            // `pendingRoleChange` being non-nil means we're already mid-
            // confirmation; suppress to avoid double-prompting.
            guard hasInitializedRole, pendingRoleChange == nil else { return }
            guard newValue != originalRole else { return }
            pendingRoleChange = newValue
            showingRoleChangeAlert = true
        }
        .onChange(of: viewModel.userRoles) { _, _ in
            // viewModel.loadData() resolves roles asynchronously. Once the
            // role for this employee lands, sync the picker to it (only
            // until the user has actually started touching it themselves).
            if !hasInitializedRole {
                let role = viewModel.role(for: employee.id)
                selectedRole = role
                originalRole = role
                hasInitializedRole = true
            }
        }
        .onAppear {
            print("🔵 EditManagerEmployeeView - ON APPEAR")
            print("   Employee: \(employee.name) (ID: \(employee.id))")
            print("   ViewModel locations count: \(viewModel.locations.count)")
            print("   hasLoadedData: \(hasLoadedData)")

            // If the role for this employee is already cached on the
            // view model (because the executive previously visited this
            // tab in the same session), seed the picker straight away.
            // Otherwise the .onChange observer above will pick it up
            // once loadData completes.
            if !hasInitializedRole, viewModel.userRoles[employee.id] != nil {
                let role = viewModel.role(for: employee.id)
                selectedRole = role
                originalRole = role
                hasInitializedRole = true
            }

            // Only load viewModel data once if needed
            if !hasLoadedData && viewModel.locations.isEmpty {
                Task {
                    print("🔵 EditManagerEmployeeView - TASK STARTED")
                    print("   Loading viewModel data for employee: \(employee.name)")
                    await viewModel.loadData()
                    print("🔵 EditManagerEmployeeView - DATA LOADED")
                    print("   ViewModel locations count after load: \(viewModel.locations.count)")
                    // Check for conflicts after loading locations
                    for locationId in selectedLocationIds {
                        checkConflicts(for: locationId)
                    }
                    hasLoadedData = true
                }
            } else {
                // Check for conflicts if locations are already loaded
                if !viewModel.locations.isEmpty {
                    for locationId in selectedLocationIds {
                        checkConflicts(for: locationId)
                    }
                }
                hasLoadedData = true
            }
        }
        .id(employee.id) // Stabilize the view with employee ID
    }
    
    private var generatedEmail: String {
        return "\(employee.username)@oplix.app"
    }

    // MARK: - Form sections
    //
    // These are extracted into computed @ViewBuilder properties so the
    // SwiftUI type checker doesn't have to digest the entire Form in a
    // single expression. With every section inline, body got past the
    // "unable to type-check this expression in reasonable time" cliff.

    /// Selected locations in stable id order, resolved up front so `ForEach`
    /// does not nest `if let` + `locationScheduleRow` in one huge builder.
    private var selectedLocationsForEditor: [Location] {
        Array(selectedLocationIds)
            .sorted()
            .compactMap { id in viewModel.locations.first { $0.id == id } }
    }

    private var unselectedLocationsForEditor: [Location] {
        viewModel.locations.filter { !selectedLocationIds.contains($0.id) }
    }

    @ViewBuilder
    private var scheduleConflictBannerSection: some View {
        if hasScheduleConflicts {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule Conflicts Detected")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("Fix overlapping shift times between locations before saving.")
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var employeeDetailsSection: some View {
        Section("Employee Details") {
            TextField("Employee Name", text: $name)
                .textInputAutocapitalization(.words)
            HStack(spacing: 8) {
                Group {
                    if showPlaintextPassword {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                Button {
                    showPlaintextPassword.toggle()
                } label: {
                    Image(systemName: showPlaintextPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                        .accessibilityLabel(showPlaintextPassword ? "Hide password" : "Show password")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var assignToLocationsSection: some View {
        Section("Assign to Locations") {
            if viewModel.locations.isEmpty {
                Text("No locations available")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
            } else {
                assignToLocationsSelectedRows
                assignToLocationsUnselectedRows
            }
        }
    }

    @ViewBuilder
    private var assignToLocationsSelectedRows: some View {
        ForEach(selectedLocationsForEditor) { location in
            locationScheduleRow(for: location)
        }
    }

    @ViewBuilder
    private var assignToLocationsUnselectedRows: some View {
        ForEach(unselectedLocationsForEditor) { location in
            Toggle(location.name, isOn: locationSelectionBinding(for: location))
        }
    }

    @ViewBuilder
    private var scheduleSettingsSection: some View {
        Section {
            Toggle("24/7", isOn: $is24Hours)
                .onChange(of: is24Hours) { _, newValue in
                    if newValue {
                        scheduleConflicts.removeAll()
                        for locationId in selectedLocationIds {
                            locationUseWeeklySchedule[locationId] = false
                        }
                    } else {
                        for locationId in selectedLocationIds {
                            checkConflicts(for: locationId)
                        }
                    }
                }
        } header: {
            Text("Schedule Settings")
        } footer: {
            if is24Hours {
                Text("24/7 shift time allows this employee at multiple locations without overlap warnings.")
            }
        }
    }

    @ViewBuilder
    private var compensationSection: some View {
        Section("Compensation") {
            TextField("Hourly Rate (e.g., 25.50)", text: $hourlyRate)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var roleSection: some View {
        Section {
            Picker("Role", selection: $selectedRole) {
                Text("Employee").tag(User.UserRole.employee)
                Text("Supervisor").tag(User.UserRole.supervisor)
            }
            .pickerStyle(.segmented)
            .oplixSegmentedPickerTint()
        } header: {
            Text("Role")
        } footer: {
            roleSectionFooter
        }
    }

    @ViewBuilder
    private var roleSectionFooter: some View {
        if selectedRole != originalRole {
            let message = selectedRole == .supervisor
                ? "On save, \(employee.name) will be promoted to supervisor. They'll need to log out and back in to see supervisor controls."
                : "On save, \(employee.name) will be demoted to a regular employee. All supervisor permissions will be cleared. They'll need to log out and back in for the change to take effect."
            Text(message)
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        Section("Permissions") {
            Toggle("Can Take Register", isOn: $canTakeRegister)
            Toggle("Can Submit Lottery", isOn: $canSubmitLottery)
        }
    }

    @ViewBuilder
    private var supervisorPermissionsSection: some View {
        Section {
            Toggle("Can View Employee Data", isOn: $canViewEmployeeData)
            Toggle("Can Manage Tasks", isOn: $canManageTasks)
            Toggle("Can Manage Documents", isOn: $canManageDocuments)
            Toggle("Can Edit Schedules", isOn: $canEditSchedules)
            Toggle("Can View Register Data", isOn: $canViewRegisterData)
            Toggle("Can View Lottery Data", isOn: $canViewLotteryData)
            Toggle("Can View Reports", isOn: $canViewReports)
        } header: {
            Text("Supervisor Permissions")
        } footer: {
            Text("Controls what this supervisor can do from their Supervisor tab.")
        }
    }

    @ViewBuilder
    private var loginCredentialsSection: some View {
        Section("Login Credentials") {
            HStack {
                Text("Username")
                Spacer()
                Text(employee.username)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            HStack {
                Text("Email")
                Spacer()
                Text(generatedEmail)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Button(action: { showingChangePassword = true }) {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(Theme.cloudBlue)
                    Text(passwordButtonLabel)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var passwordButtonLabel: String {
        let stored = employee.password
        let hasPassword = !(stored == nil || stored?.isEmpty == true)
        return hasPassword ? "Change Password" : "Set Password"
    }
    
    private func loadEmployeeData() {
        print("🔵 EditManagerEmployeeView - loadEmployeeData() STARTED")
        print("   Employee name: \(employee.name)")
        print("   Assigned location IDs: \(employee.assignedLocationIds)")
        print("   Has weekly schedule: \(employee.weeklySchedule != nil)")
        print("   Has working hours: \(employee.workingHoursStart != nil && employee.workingHoursEnd != nil)")
        
        name = employee.name
        password = employee.password ?? ""
        selectedLocationIds = Set(employee.assignedLocationIds)
        canTakeRegister = employee.hasRegisterPermission
        canSubmitLottery = employee.hasLotteryPermission
        
        print("   Set selectedLocationIds: \(selectedLocationIds)")
        
        if let rate = employee.hourlyRate {
            hourlyRate = String(format: "%.2f", rate)
            print("   Hourly rate: \(hourlyRate)")
        }
        
        // Load schedules for each assigned location
        for locationId in employee.assignedLocationIds {
            print("   Processing location: \(locationId)")
            if let schedule = employee.weeklySchedule {
                locationSchedules[locationId] = schedule
                locationUseWeeklySchedule[locationId] = true
                print("     - Using weekly schedule")
            } else if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                locationHasWorkingHours[locationId] = true
                locationWorkingHoursStart[locationId] = parseTimeString(startTime)
                locationWorkingHoursEnd[locationId] = parseTimeString(endTime)
                locationUseWeeklySchedule[locationId] = false
                print("     - Using working hours: \(startTime) - \(endTime)")
            } else {
                print("     - No schedule or working hours found")
            }
        }
        
        print("   Location schedules loaded: \(locationSchedules.count)")
        
        // Check for conflicts after loading
        for locationId in selectedLocationIds {
            checkConflicts(for: locationId)
        }
        
        print("🔵 EditManagerEmployeeView - loadEmployeeData() COMPLETED")
    }
    
    private func parseTimeString(_ timeString: String) -> Date {
        let components = timeString.split(separator: ":")
        var dateComponents = DateComponents()
        if components.count == 2,
           let hour = Int(components[0]),
           let minute = Int(components[1]) {
            dateComponents.hour = hour
            dateComponents.minute = minute
        }
        return Calendar.current.date(from: dateComponents) ?? Date()
    }

    /// Selection + schedule side effects for a location toggle. Pulled out of
    /// the view tree so SwiftUI's type checker is not asked to infer a huge
    /// nested `Binding` inside `ForEach` / `locationScheduleRow`.
    private func locationSelectionBinding(for location: Location) -> Binding<Bool> {
        Binding(
            get: { selectedLocationIds.contains(location.id) },
            set: { isOn in
                if isOn {
                    selectedLocationIds.insert(location.id)
                    if locationSchedules[location.id] == nil {
                        locationSchedules[location.id] = employee.weeklySchedule ?? WeeklySchedule()
                        locationUseWeeklySchedule[location.id] = employee.weeklySchedule != nil
                        locationHasWorkingHours[location.id] =
                            employee.workingHoursStart != nil && employee.workingHoursEnd != nil
                        if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                            locationWorkingHoursStart[location.id] = parseTimeString(startTime)
                            locationWorkingHoursEnd[location.id] = parseTimeString(endTime)
                        }
                    }
                    checkConflicts(for: location.id)
                } else {
                    selectedLocationIds.remove(location.id)
                    locationSchedules.removeValue(forKey: location.id)
                    locationUseWeeklySchedule.removeValue(forKey: location.id)
                    locationHasWorkingHours.removeValue(forKey: location.id)
                    locationWorkingHoursStart.removeValue(forKey: location.id)
                    locationWorkingHoursEnd.removeValue(forKey: location.id)
                    scheduleConflicts.removeValue(forKey: location.id)
                    for remainingLocationId in selectedLocationIds {
                        checkConflicts(for: remainingLocationId)
                    }
                }
            }
        )
    }
    
    private func updateEmployee() async {
        do {
            // Use the first location's schedule, or create a default one
            let firstLocationId = selectedLocationIds.first
            let schedule: WeeklySchedule?
            let startTime: String?
            let endTime: String?
            
            if let locationId = firstLocationId {
                if let useWeekly = locationUseWeeklySchedule[locationId], useWeekly {
                    schedule = locationSchedules[locationId]
                    startTime = nil
                    endTime = nil
                } else if let hasHours = locationHasWorkingHours[locationId], hasHours {
                    schedule = nil
                    // Get the actual stored time, or use the default from DatePicker if not set
                    let startDate: Date
                    if let storedStart = locationWorkingHoursStart[locationId] {
                        startDate = storedStart
                    } else {
                        var components = DateComponents()
                        components.hour = 9
                        components.minute = 0
                        startDate = Calendar.current.date(from: components) ?? Date()
                    }
                    
                    let endDate: Date
                    if let storedEnd = locationWorkingHoursEnd[locationId] {
                        endDate = storedEnd
                    } else {
                        var components = DateComponents()
                        components.hour = 17
                        components.minute = 0
                        endDate = Calendar.current.date(from: components) ?? Date()
                    }
                    
                    startTime = formatTime(startDate)
                    endTime = formatTime(endDate)
                } else {
                    schedule = nil
                    startTime = nil
                    endTime = nil
                }
            } else {
                schedule = nil
                startTime = nil
                endTime = nil
            }
            
            let rate = hourlyRate.isEmpty ? nil : Double(hourlyRate)
            let assignedLocationIds = Array(selectedLocationIds)
            
            var updatedEmployee = employee
            updatedEmployee.name = name
            updatedEmployee.assignedLocationIds = assignedLocationIds
            updatedEmployee.weeklySchedule = schedule
            updatedEmployee.workingHoursStart = startTime
            updatedEmployee.workingHoursEnd = endTime
            updatedEmployee.is24Hours = is24Hours // Save 24/7 status
            updatedEmployee.hourlyRate = rate
            updatedEmployee.canTakeRegister = canTakeRegister
            updatedEmployee.canSubmitLottery = canSubmitLottery

            // Supervisor-only flags. For supervisors we write the
            // current toggle state. For regular employees we explicitly
            // write `false` for all of them — important on demote so the
            // supervisor section doesn't keep granting access to a user
            // whose role is now `.employee`. (For an employee who was
            // never promoted these were already false, so this is a
            // safe no-op.)
            if isSupervisor {
                updatedEmployee.canViewEmployeeData = canViewEmployeeData
                updatedEmployee.canManageTasks = canManageTasks
                updatedEmployee.canManageDocuments = canManageDocuments
                updatedEmployee.canEditSchedules = canEditSchedules
                updatedEmployee.canViewRegisterData = canViewRegisterData
                updatedEmployee.canViewLotteryData = canViewLotteryData
                updatedEmployee.canViewReports = canViewReports
            } else {
                updatedEmployee.canViewEmployeeData = false
                updatedEmployee.canManageTasks = false
                updatedEmployee.canManageDocuments = false
                updatedEmployee.canEditSchedules = false
                updatedEmployee.canViewRegisterData = false
                updatedEmployee.canViewLotteryData = false
                updatedEmployee.canViewReports = false
            }

            print("🔵 Saving employee with is24Hours: \(is24Hours)")
            try await viewModel.updateEmployee(updatedEmployee)
            print("🔵 Employee saved successfully with is24Hours: \(is24Hours)")

            // Promote / demote the User document if the picker changed.
            // We do this AFTER updateEmployee so the supervisor-flag
            // clear has already landed in Firestore — that way there's
            // no in-between state where User.role == .employee but the
            // Employee record still has supervisor flags set.
            if selectedRole != originalRole {
                try await viewModel.updateUserRole(
                    employeeId: employee.id,
                    newRole: selectedRole
                )
                originalRole = selectedRole
            }

            // Update password if changed
            if !password.isEmpty && password != employee.password {
                try await viewModel.updateEmployeePassword(employeeId: employee.id, newPassword: password)
            }

            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    @ViewBuilder
    private func locationScheduleRow(for location: Location) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Location Toggle
            Toggle(location.name, isOn: locationSelectionBinding(for: location))
            
            // Schedule Editor (shown when location is selected)
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Text("Schedule for \(location.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    // Show conflict warning
                    if !is24Hours,
                       let locationConflicts = scheduleConflicts[location.id],
                       !locationConflicts.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Conflicts with: \(locationConflicts.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Toggle("Set Weekly Schedule", isOn: Binding(
                    get: { locationUseWeeklySchedule[location.id] ?? true },
                    set: {
                        locationUseWeeklySchedule[location.id] = $0
                        // When weekly schedule is enabled, disable 24/7
                        if $0 {
                            is24Hours = false
                        }
                        checkConflicts(for: location.id)
                    }
                ))
                .disabled(is24Hours)
                .foregroundColor(is24Hours ? Theme.darkGray : .primary)
                
                if locationUseWeeklySchedule[location.id] ?? true && !is24Hours {
                    WeeklyScheduleEditor(schedule: Binding(
                        get: { locationSchedules[location.id] ?? WeeklySchedule() },
                        set: {
                            locationSchedules[location.id] = $0
                            checkConflicts(for: location.id)
                        }
                    ))
                    .disabled(is24Hours)
                    .opacity(is24Hours ? 0.5 : 1.0)
                } else if !is24Hours {
                    Toggle("Set Working Hours", isOn: Binding(
                        get: { locationHasWorkingHours[location.id] ?? false },
                        set: {
                            locationHasWorkingHours[location.id] = $0
                            // Initialize default times if not already set when toggling on
                            if $0 {
                                if locationWorkingHoursStart[location.id] == nil {
                                    var components = DateComponents()
                                    components.hour = 9
                                    components.minute = 0
                                    locationWorkingHoursStart[location.id] = Calendar.current.date(from: components) ?? Date()
                                }
                                if locationWorkingHoursEnd[location.id] == nil {
                                    var components = DateComponents()
                                    components.hour = 17
                                    components.minute = 0
                                    locationWorkingHoursEnd[location.id] = Calendar.current.date(from: components) ?? Date()
                                }
                            }
                            checkConflicts(for: location.id)
                        }
                    ))
                    
                    if locationHasWorkingHours[location.id] ?? false {
                        DatePicker("Start Time", selection: Binding(
                            get: {
                                if let date = locationWorkingHoursStart[location.id] {
                                    return date
                                }
                                var components = DateComponents()
                                components.hour = 9
                                components.minute = 0
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: {
                                locationWorkingHoursStart[location.id] = $0
                                checkConflicts(for: location.id)
                            }
                        ), displayedComponents: .hourAndMinute)
                        
                        DatePicker("End Time", selection: Binding(
                            get: {
                                if let date = locationWorkingHoursEnd[location.id] {
                                    return date
                                }
                                var components = DateComponents()
                                components.hour = 17
                                components.minute = 0
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: {
                                locationWorkingHoursEnd[location.id] = $0
                                checkConflicts(for: location.id)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private var hasScheduleConflicts: Bool {
        !is24Hours && !scheduleConflicts.isEmpty
    }
    
    private func checkConflicts(for locationId: String) {
        if is24Hours {
            scheduleConflicts.removeValue(forKey: locationId)
            return
        }

        var conflicts: [String] = []
        
        guard viewModel.locations.first(where: { $0.id == locationId }) != nil else { return }
        
        // Get current location's schedule
        let currentUseWeekly = locationUseWeeklySchedule[locationId] ?? true
        let currentSchedule = locationSchedules[locationId] ?? WeeklySchedule()
        let currentHasHours = locationHasWorkingHours[locationId] ?? false
        let currentStart = locationWorkingHoursStart[locationId]
        let currentEnd = locationWorkingHoursEnd[locationId]
        
        // Check against all other selected locations
        for otherLocationId in selectedLocationIds where otherLocationId != locationId {
            guard let otherLocation = viewModel.locations.first(where: { $0.id == otherLocationId }) else { continue }
            
            let otherUseWeekly = locationUseWeeklySchedule[otherLocationId] ?? true
            let otherSchedule = locationSchedules[otherLocationId] ?? WeeklySchedule()
            let otherHasHours = locationHasWorkingHours[otherLocationId] ?? false
            let otherStart = locationWorkingHoursStart[otherLocationId]
            let otherEnd = locationWorkingHoursEnd[otherLocationId]
            
            // Check for conflicts
            if currentUseWeekly && otherUseWeekly {
                // Both use weekly schedules - check for overlapping days/times
                if schedulesOverlap(currentSchedule, otherSchedule) {
                    conflicts.append(otherLocation.name)
                }
            } else if !currentUseWeekly && !otherUseWeekly && currentHasHours && otherHasHours {
                // Both use simple working hours - check if times overlap
                if let cStart = currentStart, let cEnd = currentEnd,
                   let oStart = otherStart, let oEnd = otherEnd {
                    if timesOverlap(cStart, cEnd, oStart, oEnd) {
                        conflicts.append(otherLocation.name)
                    }
                }
            } else if currentUseWeekly && !otherUseWeekly && otherHasHours {
                // Current uses weekly, other uses simple hours
                if let oStart = otherStart, let oEnd = otherEnd {
                    if weeklyScheduleOverlapsWithHours(currentSchedule, start: oStart, end: oEnd) {
                        conflicts.append(otherLocation.name)
                    }
                }
            } else if !currentUseWeekly && currentHasHours && otherUseWeekly {
                // Current uses simple hours, other uses weekly
                if let cStart = currentStart, let cEnd = currentEnd {
                    if weeklyScheduleOverlapsWithHours(otherSchedule, start: cStart, end: cEnd) {
                        conflicts.append(otherLocation.name)
                    }
                }
            }
        }
        
        if conflicts.isEmpty {
            scheduleConflicts.removeValue(forKey: locationId)
        } else {
            scheduleConflicts[locationId] = conflicts
        }
    }
    
    private func schedulesOverlap(_ schedule1: WeeklySchedule, _ schedule2: WeeklySchedule) -> Bool {
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        
        for day in days {
            let daySchedule1: WeeklySchedule.DaySchedule?
            let daySchedule2: WeeklySchedule.DaySchedule?
            
            switch day {
            case "monday":
                daySchedule1 = schedule1.monday
                daySchedule2 = schedule2.monday
            case "tuesday":
                daySchedule1 = schedule1.tuesday
                daySchedule2 = schedule2.tuesday
            case "wednesday":
                daySchedule1 = schedule1.wednesday
                daySchedule2 = schedule2.wednesday
            case "thursday":
                daySchedule1 = schedule1.thursday
                daySchedule2 = schedule2.thursday
            case "friday":
                daySchedule1 = schedule1.friday
                daySchedule2 = schedule2.friday
            case "saturday":
                daySchedule1 = schedule1.saturday
                daySchedule2 = schedule2.saturday
            case "sunday":
                daySchedule1 = schedule1.sunday
                daySchedule2 = schedule2.sunday
            default:
                continue
            }
            
            if let s1 = daySchedule1, let s2 = daySchedule2,
               s1.isWorking && s2.isWorking {
                if timesOverlap(s1.startTime, s1.endTime, s2.startTime, s2.endTime) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func timesOverlap(_ start1: String, _ end1: String, _ start2: String, _ end2: String) -> Bool {
        let time1Start = parseTime(start1)
        let time1End = parseTime(end1)
        let time2Start = parseTime(start2)
        let time2End = parseTime(end2)
        
        // Check if time ranges overlap
        return time1Start < time2End && time2Start < time1End
    }
    
    private func timesOverlap(_ start1: Date, _ end1: Date, _ start2: Date, _ end2: Date) -> Bool {
        let calendar = Calendar.current
        let components1 = calendar.dateComponents([.hour, .minute], from: start1)
        let components1End = calendar.dateComponents([.hour, .minute], from: end1)
        let components2 = calendar.dateComponents([.hour, .minute], from: start2)
        let components2End = calendar.dateComponents([.hour, .minute], from: end2)
        
        let time1Start = (components1.hour ?? 0) * 60 + (components1.minute ?? 0)
        let time1End = (components1End.hour ?? 0) * 60 + (components1End.minute ?? 0)
        let time2Start = (components2.hour ?? 0) * 60 + (components2.minute ?? 0)
        let time2End = (components2End.hour ?? 0) * 60 + (components2End.minute ?? 0)
        
        return time1Start < time2End && time2Start < time1End
    }
    
    private func weeklyScheduleOverlapsWithHours(_ schedule: WeeklySchedule, start: Date, end: Date) -> Bool {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        
        let startTime = "\(String(format: "%02d", startComponents.hour ?? 0)):\(String(format: "%02d", startComponents.minute ?? 0))"
        let endTime = "\(String(format: "%02d", endComponents.hour ?? 0)):\(String(format: "%02d", endComponents.minute ?? 0))"
        
        // Check if the simple hours overlap with any day in the weekly schedule
        let days = [schedule.monday, schedule.tuesday, schedule.wednesday, schedule.thursday, schedule.friday, schedule.saturday, schedule.sunday]
        
        for daySchedule in days {
            if let day = daySchedule, day.isWorking {
                if timesOverlap(startTime, endTime, day.startTime, day.endTime) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func parseTime(_ timeString: String) -> Int {
        let components = timeString.split(separator: ":")
        if components.count == 2,
           let hour = Int(components[0]),
           let minute = Int(components[1]) {
            return hour * 60 + minute
        }
        return 0
    }
}

