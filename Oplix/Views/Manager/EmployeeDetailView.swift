//
//  EmployeeDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeDetailView: View {
    let employee: Employee
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedTaskIds: Set<String> = []
    @State private var showingChangePassword = false
    @State private var newPassword = ""
    @State private var showingPasswordError = false
    @State private var passwordErrorMessage = ""
    @State private var showingPasswordSuccess = false
    @State private var canTakeRegister: Bool = false
    @State private var canSubmitLottery: Bool = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingPermissionSuccess = false

    // Supervisor-only permission state. Mirrors EditManagerEmployeeView so
    // supervisor flags are editable from either entry point. Only rendered
    // and saved when the employee actually has the supervisor role.
    @State private var canViewEmployeeData: Bool = false
    @State private var canManageTasks: Bool = false
    @State private var canManageDocuments: Bool = false
    @State private var canViewRegisterData: Bool = false
    @State private var canViewLotteryData: Bool = false
    @State private var canEditSchedules: Bool = false
    @State private var canViewReports: Bool = false
    @State private var canManagePayroll: Bool = false

    /// True when this employee was loaded into the view model's
    /// `supervisors` bucket. The view model populates that bucket by
    /// fetching User.role, so this is a reliable proxy without a duplicate
    /// network request from this screen.
    private var isSupervisor: Bool {
        viewModel.supervisors.contains(where: { $0.id == employee.id })
    }
    @State private var showingEditHourlyRate = false
    @State private var hourlyRateText = ""
    @State private var showingHourlyRateError = false
    @State private var hourlyRateErrorMessage = ""
    @State private var showingHourlyRateSuccess = false
    @State private var employeeSchedule: WeeklySchedule?
    @State private var hasSchedule = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Employee Info Card
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Theme.cloudBlue)
                        
                        Text(employee.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(employee.username)
                            .font(.subheadline)
                            .foregroundColor(Theme.darkGray)
                        
                        HStack {
                            Text("Status:")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                            Text(employee.currentShiftStatus.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(employee.currentShiftStatus == .clockedIn ? Color.green.opacity(0.2) : Theme.darkGray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cloudWhite)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    // Credentials Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Login Credentials")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            CredentialRow(label: "Username", value: employee.username, icon: "person.fill")
                            PasswordCredentialRow(
                                password: employee.password,
                                onChangePassword: {
                                    showingChangePassword = true
                                }
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Working Hours Section
                    if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Working Hours")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(Theme.cloudBlue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start Time")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(startTime)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(Theme.cloudBlue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("End Time")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(endTime)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Schedule Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Schedule")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            if hasSchedule, let schedule = employeeSchedule {
                                WeeklyScheduleEditor(schedule: Binding(
                                    get: { schedule },
                                    set: { newSchedule in
                                        employeeSchedule = newSchedule
                                        Task {
                                            var updatedEmployee = employee
                                            updatedEmployee.weeklySchedule = newSchedule
                                            do {
                                                try await viewModel.updateEmployee(updatedEmployee)
                                            } catch {
                                                // Handle error
                                            }
                                        }
                                    }
                                ))
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            } else {
                                VStack(spacing: 8) {
                                    Text("No weekly schedule set")
                                        .font(.subheadline)
                                        .foregroundColor(Theme.darkGray)
                                    
                                    Button(action: {
                                        let newSchedule = WeeklySchedule()
                                        employeeSchedule = newSchedule
                                        hasSchedule = true
                                        Task {
                                            var updatedEmployee = employee
                                            updatedEmployee.weeklySchedule = newSchedule
                                            do {
                                                try await viewModel.updateEmployee(updatedEmployee)
                                            } catch {
                                                // Handle error
                                            }
                                        }
                                    }) {
                                        Text("Add Weekly Schedule")
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Theme.cloudBlue)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Hourly Rate Section (Always shown)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Compensation")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(Theme.cloudBlue)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hourly Rate")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let rate = employee.hourlyRate {
                                    Text(formatCurrency(rate))
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Not set")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                // Pre-fill with current rate if exists
                                if let rate = employee.hourlyRate {
                                    hourlyRateText = String(format: "%.2f", rate)
                                } else {
                                    hourlyRateText = ""
                                }
                                showingEditHourlyRate = true
                            }) {
                                Image(systemName: employee.hourlyRate == nil ? "plus.circle.fill" : "pencil.circle.fill")
                                    .foregroundColor(Theme.cloudBlue)
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(Theme.cloudWhite)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .padding(.horizontal)
                    }
                    
                    // Permissions Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Permissions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Toggle(isOn: $canTakeRegister) {
                                HStack {
                                    Image(systemName: "cashregister.fill")
                                        .foregroundColor(Theme.cloudBlue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Can Take Register")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Allow employee to enter shift register data")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Theme.cloudWhite)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            
                            Toggle(isOn: $canSubmitLottery) {
                                HStack {
                                    Image(systemName: "ticket.fill")
                                        .foregroundColor(Theme.cloudBlue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Can Submit Lottery")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text("Allow employee to submit lottery forms")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Theme.cloudWhite)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

                            // Supervisor-only permissions. Only shown for
                            // people whose User.role is .supervisor — for
                            // regular employees these are irrelevant and
                            // would just clutter the screen.
                            if isSupervisor {
                                supervisorPermissionToggle(
                                    isOn: $canViewEmployeeData,
                                    icon: "person.2.fill",
                                    title: "Can View Employee Data",
                                    subtitle: "View other employees and their shifts"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canManageTasks,
                                    icon: "checklist",
                                    title: "Can Manage Tasks",
                                    subtitle: "Audit, approve photos, add/edit tasks at this location"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canManageDocuments,
                                    icon: "doc.text.fill",
                                    title: "Can Manage Documents",
                                    subtitle: "Upload and manage documents for this location"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canEditSchedules,
                                    icon: "calendar",
                                    title: "Can Edit Schedules",
                                    subtitle: "Modify employee schedules at this location"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canViewRegisterData,
                                    icon: "cashregister",
                                    title: "Can View Register Data",
                                    subtitle: "Read-only access to register submissions"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canViewLotteryData,
                                    icon: "ticket",
                                    title: "Can View Lottery Data",
                                    subtitle: "Read-only access to lottery forms"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canViewReports,
                                    icon: "chart.bar.fill",
                                    title: "Can View Reports",
                                    subtitle: "Access reports and statistics"
                                )
                                supervisorPermissionToggle(
                                    isOn: $canManagePayroll,
                                    icon: "dollarsign.circle.fill",
                                    title: "Can Manage Payroll",
                                    subtitle: "Run payroll, view history, and print pay sheets"
                                )
                            }

                            Button(action: {
                                Task {
                                    await updatePermissions()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Save Permissions")
                                }
                                .frame(maxWidth: .infinity)
                                .cloudButton(backgroundColor: .blue)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Assign Tasks Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Assign Tasks")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if viewModel.tasks.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No tasks available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.tasks) { task in
                                TaskAssignmentRow(
                                    task: task,
                                    employee: employee,
                                    isSelected: selectedTaskIds.contains(task.id),
                                    isAssignedToThisEmployee: task.isAssignedTo(employeeId: employee.id)
                                ) {
                                    if task.isAssignedTo(employeeId: employee.id) {
                                        // Unassign
                                        Task {
                                            await viewModel.unassignTask(task, fromEmployeeId: employee.id)
                                        }
                                    } else {
                                        // Assign
                                        Task {
                                            await viewModel.assignTask(task, toEmployeeId: employee.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(employee.name)
        .navigationBarTitleDisplayMode(.large)
                .onAppear {
                    // Pre-select tasks already assigned to this employee
                    selectedTaskIds = Set(viewModel.tasks.filter { $0.isAssignedTo(employeeId: employee.id) }.map { $0.id })
                    // Initialize permission toggles
                    canTakeRegister = employee.hasRegisterPermission
                    canSubmitLottery = employee.hasLotteryPermission
                    // Supervisor-only flags — safe to read for any employee;
                    // they just default to false on records that never set
                    // them. The UI only surfaces these when isSupervisor.
                    canViewEmployeeData = employee.canViewEmployeeData ?? false
                    canManageTasks = employee.canManageTasks ?? false
                    canManageDocuments = employee.canManageDocuments ?? false
                    canViewRegisterData = employee.canViewRegisterData ?? false
                    canViewLotteryData = employee.canViewLotteryData ?? false
                    canEditSchedules = employee.canEditSchedules ?? false
                    canViewReports = employee.canViewReports ?? false
                    canManagePayroll = employee.canManagePayroll ?? false
                    // Initialize schedule
                    if let schedule = employee.weeklySchedule {
                        employeeSchedule = schedule
                        hasSchedule = true
                    } else {
                        hasSchedule = false
                    }
                }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(
                employeeName: employee.name,
                onSave: { newPassword in
                    Task {
                        do {
                            try await viewModel.updateEmployeePassword(employeeId: employee.id, newPassword: newPassword)
                            showingPasswordSuccess = true
                            showingChangePassword = false
                        } catch {
                            passwordErrorMessage = error.localizedDescription
                            showingPasswordError = true
                        }
                    }
                },
                onCancel: {
                    showingChangePassword = false
                }
            )
        }
        .alert("Error", isPresented: $showingPasswordError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(passwordErrorMessage)
        }
        .alert("Success", isPresented: $showingPasswordSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Password updated successfully")
        }
        .alert("Error", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
        .alert("Success", isPresented: $showingPermissionSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Permissions updated successfully")
        }
        .sheet(isPresented: $showingEditHourlyRate) {
            EditHourlyRateView(
                currentRate: employee.hourlyRate,
                hourlyRateText: $hourlyRateText,
                onSave: {
                    Task {
                        await updateHourlyRate()
                    }
                },
                onCancel: {
                    showingEditHourlyRate = false
                    hourlyRateText = ""
                }
            )
        }
        .alert("Error", isPresented: $showingHourlyRateError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(hourlyRateErrorMessage)
        }
        .alert("Success", isPresented: $showingHourlyRateSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Hourly rate updated successfully")
        }
    }
    
    private func updateHourlyRate() async {
        guard !hourlyRateText.isEmpty else {
            hourlyRateErrorMessage = "Please enter an hourly rate"
            showingHourlyRateError = true
            return
        }
        
        guard let rate = Double(hourlyRateText), rate >= 0 else {
            hourlyRateErrorMessage = "Please enter a valid hourly rate (must be a positive number)"
            showingHourlyRateError = true
            return
        }
        
        do {
            var updatedEmployee = employee
            updatedEmployee.hourlyRate = rate
            try await viewModel.updateEmployee(updatedEmployee)
            showingHourlyRateSuccess = true
            showingEditHourlyRate = false
            hourlyRateText = ""
        } catch {
            hourlyRateErrorMessage = "Failed to update hourly rate: \(error.localizedDescription)"
            showingHourlyRateError = true
        }
    }
    
    private func updatePermissions() async {
        do {
            var updatedEmployee = employee
            updatedEmployee.canTakeRegister = canTakeRegister
            updatedEmployee.canSubmitLottery = canSubmitLottery

            // Only persist supervisor-only flags when the employee actually
            // has the supervisor role. For everyone else we leave the
            // existing values alone so we don't overwrite stored data with
            // stale UI state from the regular permission section.
            if isSupervisor {
                updatedEmployee.canViewEmployeeData = canViewEmployeeData
                updatedEmployee.canManageTasks = canManageTasks
                updatedEmployee.canManageDocuments = canManageDocuments
                updatedEmployee.canEditSchedules = canEditSchedules
                updatedEmployee.canViewRegisterData = canViewRegisterData
                updatedEmployee.canViewLotteryData = canViewLotteryData
                updatedEmployee.canViewReports = canViewReports
                updatedEmployee.canManagePayroll = canManagePayroll
            }

            try await viewModel.updateEmployee(updatedEmployee)
            
            // Update local state from viewModel's refreshed employee list
            if let updatedEmployeeFromViewModel = viewModel.employees.first(where: { $0.id == employee.id }) {
                // The employee constant can't be updated, but we can update the toggles
                // The viewModel's employee list is already updated, so the UI should reflect the changes
                // when the view refreshes or when navigating back and forth
            }
            
            showingPermissionSuccess = true
        } catch {
            permissionErrorMessage = "Failed to update permissions: \(error.localizedDescription)"
            showingPermissionError = true
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    /// Reusable card-styled toggle for supervisor permission rows. Keeps
    /// the visual treatment identical to the existing register/lottery
    /// toggles above so the section reads as one consistent list.
    @ViewBuilder
    private func supervisorPermissionToggle(
        isOn: Binding<Bool>,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.cloudBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct PasswordCredentialRow: View {
    let password: String?
    let onChangePassword: () -> Void
    @State private var showingPassword = false
    
    var body: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundColor(Theme.cloudBlue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(showingPassword ? (password ?? "Not set") : (password != nil ? "••••••" : "Not set"))
                    .font(.body)
                    .foregroundColor(password != nil ? .primary : .secondary)
            }
            
            Spacer()
            
            if password != nil {
                Button(action: {
                    showingPassword.toggle()
                }) {
                    Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: onChangePassword) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(Theme.cloudBlue)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct ChangePasswordView: View {
    let employeeName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Change Password for \(employeeName)") {
                        SecureField("New Password", text: $newPassword)
                        SecureField("Confirm Password", text: $confirmPassword)
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if newPassword == confirmPassword {
                            if !newPassword.isEmpty {
                                onSave(newPassword)
                            }
                        }
                    }
                    .disabled(newPassword.isEmpty || confirmPassword.isEmpty || newPassword != confirmPassword)
                }
            }
        }
    }
}

struct CredentialRow: View {
    let label: String
    let value: String
    let icon: String
    var isPassword: Bool = false
    @State private var showingPassword = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.cloudBlue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(isPassword && !showingPassword ? "••••••" : value)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            if isPassword {
                Button(action: {
                    showingPassword.toggle()
                }) {
                    Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: {
                    UIPasteboard.general.string = value
                }) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct TaskAssignmentRow: View {
    let task: WorkTask
    let employee: Employee
    let isSelected: Bool
    let isAssignedToThisEmployee: Bool
    let onToggle: () -> Void
    @State private var showingImage = false
    
    private var isCompletedByThisEmployee: Bool {
        task.isCompletedBy(employeeId: employee.id)
    }
    
    private var completion: TaskCompletion? {
        task.getCompletion(for: employee.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isAssignedToThisEmployee ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isAssignedToThisEmployee ? .green : .gray)
                        .font(.title3)
                }
                .disabled(isCompletedByThisEmployee)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.description)
                        .font(.body)
                        .strikethrough(isCompletedByThisEmployee)
                        .foregroundColor(isCompletedByThisEmployee ? .secondary : .primary)
                    
                    if isAssignedToThisEmployee {
                        if isCompletedByThisEmployee {
                            Text("Completed by this employee")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Assigned to this employee")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if !task.assignedEmployeeIds.isEmpty {
                        Text("Assigned to \(task.assignedEmployeeIds.count) employee(s)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("Unassigned")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Show completion badge only if assigned to this employee and completed
                if isCompletedByThisEmployee {
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            // Show completion image if task is completed by this employee
            if let completion = completion {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: {
                        showingImage = true
                    }) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text("View Completion Photo")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    Text("Completed: \(completion.timestamp, style: .date) at \(completion.timestamp, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .opacity(isCompletedByThisEmployee ? 0.6 : 1.0)
        .sheet(isPresented: $showingImage) {
            if let completion = completion {
                let allURLs = completion.imageURLs.isEmpty ? [completion.imageURL] : completion.imageURLs
                if allURLs.count > 1 {
                    TaskImagesView(imageURLs: allURLs, timestamp: completion.timestamp)
                } else {
                    TaskImageView(imageURL: allURLs.first ?? completion.imageURL, timestamp: completion.timestamp, employeeName: nil)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmployeeDetailView(
            employee: Employee(
                id: "test",
                name: "John Doe",
                username: "johndoe",
                locationId: "loc1",
                managerUserId: "manager1",
                password: "123456",
                shiftHistory: [],
                currentShiftStatus: .clockedOut
            ),
            viewModel: LocationDetailViewModel(userId: "test-user", locationId: "test-location")
        )
    }
}

// MARK: - Edit Hourly Rate View
struct EditHourlyRateView: View {
    let currentRate: Double?
    @Binding var hourlyRateText: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section {
                        TextField("Hourly Rate (e.g., 25.50)", text: $hourlyRateText)
                            .keyboardType(.decimalPad)
                        
                        if let currentRate = currentRate {
                            Text("Current rate: \(formatCurrency(currentRate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No hourly rate currently set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Hourly Rate")
                    } footer: {
                        Text("Enter the employee's hourly pay rate. This will be used for payroll calculations.")
                    }
                }
            }
            .navigationTitle(currentRate == nil ? "Set Hourly Rate" : "Edit Hourly Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(hourlyRateText.isEmpty)
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

