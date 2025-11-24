//
//  ManagerEmployeeDetailView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct ManagerEmployeeDetailView: View {
    @State private var employee: Employee
    @ObservedObject var viewModel: ManagerEmployeesViewModel
    @Environment(\.dismiss) var dismiss
    
    init(employee: Employee, viewModel: ManagerEmployeesViewModel) {
        _employee = State(initialValue: employee)
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }
    
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedPassword: String = ""
    @State private var showingPassword = false
    @State private var showingChangePassword = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showingPasswordError = false
    @State private var passwordErrorMessage = ""
    @State private var showingPasswordSuccess = false
    @State private var canTakeRegister: Bool = false
    @State private var canSubmitLottery: Bool = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingEditHourlyRate = false
    @State private var hourlyRateText = ""
    @State private var showingHourlyRateError = false
    @State private var hourlyRateErrorMessage = ""
    @State private var showingHourlyRateSuccess = false
    @State private var showingEditSchedule = false
    @State private var selectedLocationIds: Set<String> = []
    @State private var showingLocationAssignment = false
    @State private var showingScheduleForNewLocation = false
    @State private var newLocationSchedule: WeeklySchedule = WeeklySchedule()
    @State private var pendingLocationIds: Set<String> = []
    
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
                        
                        if isEditing {
                            TextField("Employee Name", text: $editedName)
                                .font(.title)
                                .fontWeight(.bold)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(employee.name)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        
                        Text(employee.username)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Status:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(employee.currentShiftStatus.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(employee.currentShiftStatus == .clockedIn ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
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
                        HStack {
                            Text("Login Credentials")
                                .font(.headline)
                            Spacer()
                            if isEditing {
                                Button("Save") {
                                    Task {
                                        await saveName()
                                    }
                                }
                                .foregroundColor(Theme.cloudBlue)
                            } else {
                                Button("Edit") {
                                    isEditing = true
                                    editedName = employee.name
                                }
                                .foregroundColor(Theme.cloudBlue)
                            }
                        }
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
                    
                    // Working Hours / Schedule Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Working Schedule")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                showingEditSchedule = true
                            }) {
                                Image(systemName: employee.weeklySchedule != nil ? "pencil.circle.fill" : "plus.circle.fill")
                                    .foregroundColor(Theme.cloudBlue)
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal)
                        
                        if let schedule = employee.weeklySchedule {
                            WeeklyScheduleDisplayCard(schedule: schedule)
                                .padding(.horizontal)
                        } else if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
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
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No schedule set")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Hourly Rate Section
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
                    
                    // Location Assignments Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Location Assignments")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                showingLocationAssignment = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Theme.cloudBlue)
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal)
                        
                        if employee.assignedLocationIds.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No locations assigned")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .padding(.horizontal)
                        } else {
                            ForEach(employee.assignedLocationIds, id: \.self) { locationId in
                                if let location = viewModel.locations.first(where: { $0.id == locationId }) {
                                    HStack {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundColor(Theme.cloudBlue)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(location.name)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(location.address)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            Task {
                                                await viewModel.unassignEmployeeFromLocation(employeeId: employee.id, locationId: locationId)
                                                // Refresh employee data
                                                await viewModel.loadData()
                                                if let updated = viewModel.employees.first(where: { $0.id == employee.id }) {
                                                    employee = updated
                                                }
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding()
                                    .background(Theme.cloudWhite)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
            canTakeRegister = employee.hasRegisterPermission
            canSubmitLottery = employee.hasLotteryPermission
            selectedLocationIds = Set(employee.assignedLocationIds)
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
        .sheet(isPresented: $showingEditSchedule) {
            WeeklyScheduleEditorView(
                schedule: employee.weeklySchedule,
                onSave: { schedule in
                    Task {
                        await updateSchedule(schedule)
                    }
                },
                onCancel: {
                    showingEditSchedule = false
                }
            )
        }
        .sheet(isPresented: $showingLocationAssignment) {
            LocationAssignmentView(
                employee: employee,
                viewModel: viewModel,
                selectedLocationIds: $selectedLocationIds,
                onSave: {
                    // Check if this is adding a 2nd+ location
                    let currentLocationIds = Set(employee.assignedLocationIds)
                    let newLocationIds = selectedLocationIds
                    let locationsToAdd = newLocationIds.subtracting(currentLocationIds)
                    
                    // If adding locations and employee already has at least one location, prompt for schedule
                    if !locationsToAdd.isEmpty && !currentLocationIds.isEmpty {
                        pendingLocationIds = locationsToAdd
                        newLocationSchedule = employee.weeklySchedule ?? WeeklySchedule()
                        showingScheduleForNewLocation = true
                    } else {
                        Task {
                            await saveLocationAssignments()
                        }
                    }
                },
                onCancel: {
                    showingLocationAssignment = false
                }
            )
        }
        .sheet(isPresented: $showingScheduleForNewLocation) {
            NavigationStack {
                ZStack {
                    Theme.secondaryGradient
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Text("Set Working Hours for New Location(s)")
                            .font(.headline)
                            .padding(.top)
                        
                        Text("Please set the working schedule for the newly assigned location(s).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        WeeklyScheduleEditor(schedule: $newLocationSchedule)
                    }
                }
                .navigationTitle("Set Schedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingScheduleForNewLocation = false
                            showingLocationAssignment = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await saveLocationAssignmentsWithSchedule()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func saveName() async {
        guard !editedName.isEmpty else { return }
        
        var updatedEmployee = employee
        updatedEmployee.name = editedName
        // Note: Username is auto-generated from name, but we won't change it after creation
        // to avoid breaking authentication
        
        do {
            try await viewModel.updateEmployee(updatedEmployee)
            employee = updatedEmployee
            isEditing = false
        } catch {
            // Handle error
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
            employee = updatedEmployee
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
            
            try await viewModel.updateEmployee(updatedEmployee)
            employee = updatedEmployee
        } catch {
            permissionErrorMessage = "Failed to update permissions: \(error.localizedDescription)"
            showingPermissionError = true
        }
    }
    
    private func updateSchedule(_ schedule: WeeklySchedule?) async {
        var updatedEmployee = employee
        updatedEmployee.weeklySchedule = schedule
        do {
            try await viewModel.updateEmployee(updatedEmployee)
            employee = updatedEmployee
            showingEditSchedule = false
        } catch {
            // Handle error
        }
    }
    
    private func saveLocationAssignments() async {
        // Get locations to add and remove
        let currentLocationIds = Set(employee.assignedLocationIds)
        let newLocationIds = selectedLocationIds
        
        let toAdd = newLocationIds.subtracting(currentLocationIds)
        let toRemove = currentLocationIds.subtracting(newLocationIds)
        
        // Add new assignments
        for locationId in toAdd {
            await viewModel.assignEmployeeToLocation(employeeId: employee.id, locationId: locationId)
        }
        
        // Remove old assignments
        for locationId in toRemove {
            await viewModel.unassignEmployeeFromLocation(employeeId: employee.id, locationId: locationId)
        }
        
        // Refresh employee data
        await viewModel.loadData()
        if let updated = viewModel.employees.first(where: { $0.id == employee.id }) {
            employee = updated
        }
        
        showingLocationAssignment = false
    }
    
    private func saveLocationAssignmentsWithSchedule() async {
        // Update employee schedule first
        var updatedEmployee = employee
        updatedEmployee.weeklySchedule = newLocationSchedule
        
        do {
            try await viewModel.updateEmployee(updatedEmployee)
            employee = updatedEmployee
        } catch {
            // Handle error
        }
        
        // Then save location assignments
        await saveLocationAssignments()
        showingScheduleForNewLocation = false
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

// MARK: - Supporting Views (using shared components from EmployeeDetailView.swift)

struct WeeklyScheduleEditorView: View {
    let schedule: WeeklySchedule?
    let onSave: (WeeklySchedule?) -> Void
    let onCancel: () -> Void
    @State private var editedSchedule: WeeklySchedule
    
    init(schedule: WeeklySchedule?, onSave: @escaping (WeeklySchedule?) -> Void, onCancel: @escaping () -> Void) {
        self.schedule = schedule
        self.onSave = onSave
        self.onCancel = onCancel
        _editedSchedule = State(initialValue: schedule ?? WeeklySchedule())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                WeeklyScheduleEditor(schedule: $editedSchedule)
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedSchedule)
                    }
                }
            }
        }
    }
}

struct LocationAssignmentView: View {
    let employee: Employee
    @ObservedObject var viewModel: ManagerEmployeesViewModel
    @Binding var selectedLocationIds: Set<String>
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Select Locations") {
                        ForEach(viewModel.locations) { location in
                            Toggle(isOn: Binding(
                                get: { selectedLocationIds.contains(location.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedLocationIds.insert(location.id)
                                    } else {
                                        selectedLocationIds.remove(location.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .font(.body)
                                    Text(location.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assign Locations")
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
                }
            }
        }
    }
}


