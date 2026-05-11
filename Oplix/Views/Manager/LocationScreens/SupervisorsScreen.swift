//
//  SupervisorsScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct SupervisorsScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingAddSupervisor = false
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.supervisors.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Supervisors")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("Tap the button below to add a supervisor")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        showingAddSupervisor = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Supervisor")
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(viewModel.supervisors) { supervisor in
                        NavigationLink(value: supervisor) {
                            EmployeeRow(employee: supervisor, tasks: viewModel.tasks)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            Task {
                                await viewModel.deleteEmployee(viewModel.supervisors[index])
                            }
                        }
                    }
                }
                .navigationDestination(for: Employee.self) { supervisor in
                    EmployeeDetailView(employee: supervisor, viewModel: viewModel)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        showingAddSupervisor = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Supervisor")
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Supervisors")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddSupervisor) {
            AddSupervisorView(viewModel: viewModel)
        }
    }
}

struct AddSupervisorView: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var workingHoursStart: Date = {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var workingHoursEnd: Date = {
        var components = DateComponents()
        components.hour = 17
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var hasWorkingHours = false
    @State private var useWeeklySchedule = true
    @State private var weeklySchedule = WeeklySchedule()
    @State private var hourlyRate = ""
    @State private var canTakeRegister = false
    @State private var canSubmitLottery = false
    // Supervisor-specific permissions
    @State private var canEditSchedules = true // Default: supervisors can edit employee schedules
    @State private var canManageTasks = true // Default: supervisors can add and check tasks
    @State private var canManageDocuments = true // Default: supervisors can add and manage documents
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var createdSupervisorInfo: (username: String, email: String, password: String)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Supervisor Details") {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                        SecureField("Password", text: $password)
                    }
                    
                    Section("Schedule") {
                        Toggle("Set Weekly Schedule", isOn: $useWeeklySchedule)
                        
                        if useWeeklySchedule {
                            WeeklyScheduleEditor(schedule: $weeklySchedule)
                        } else {
                            Toggle("Set Working Hours", isOn: $hasWorkingHours)
                            
                            if hasWorkingHours {
                                DatePicker("Start Time", selection: $workingHoursStart, displayedComponents: .hourAndMinute)
                                DatePicker("End Time", selection: $workingHoursEnd, displayedComponents: .hourAndMinute)
                            }
                        }
                    }
                    
                    Section("Compensation") {
                        TextField("Hourly Rate (e.g., 25.50)", text: $hourlyRate)
                            .keyboardType(.decimalPad)
                    }
                    
                    Section("Basic Permissions") {
                        Toggle("Can Take Register", isOn: $canTakeRegister)
                        Toggle("Can Submit Lottery", isOn: $canSubmitLottery)
                    }
                    
                    Section("Supervisor Permissions") {
                        Toggle("Can Edit Employee Schedules", isOn: $canEditSchedules)
                            .help("Allows supervisor to change schedules for employees at this location")
                        Toggle("Can Manage Tasks", isOn: $canManageTasks)
                            .help("Allows supervisor to add and check tasks for this location")
                        Toggle("Can Manage Documents", isOn: $canManageDocuments)
                            .help("Allows supervisor to add and manage documents for this location")
                    }
                    
                    Section("Auto-Generated") {
                        HStack {
                            Text("Username")
                            Spacer()
                            Text(generatedUsername)
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
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Supervisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createSupervisor()
                        }
                    }
                    .disabled(name.isEmpty || password.isEmpty)
                }
            }
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Supervisor Created Successfully", isPresented: $showingSuccess) {
                Button("Copy Password") {
                    if let password = createdSupervisorInfo?.password {
                        UIPasteboard.general.string = password
                    }
                }
                Button("Done", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let info = createdSupervisorInfo {
                    Text("Email: \(info.email)\n\nPassword: \(info.password)")
                }
            }
        }
    }
    
    private var generatedUsername: String {
        guard !name.isEmpty else { return "" }
        let username = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return username.isEmpty ? "supervisor" : username
    }
    
    private var generatedEmail: String {
        let username = generatedUsername
        return username.isEmpty ? "" : "\(username)@oplix.app"
    }
    
    private func createSupervisor() async {
        do {
            let startTime = (!useWeeklySchedule && hasWorkingHours) ? formatTime(workingHoursStart) : nil
            let endTime = (!useWeeklySchedule && hasWorkingHours) ? formatTime(workingHoursEnd) : nil
            let schedule = useWeeklySchedule ? weeklySchedule : nil
            let rate = hourlyRate.isEmpty ? nil : Double(hourlyRate)
            let info = try await viewModel.createEmployee(
                name: name,
                password: password,
                role: .supervisor,
                workingHoursStart: startTime,
                workingHoursEnd: endTime,
                weeklySchedule: schedule,
                hourlyRate: rate,
                canTakeRegister: canTakeRegister,
                canSubmitLottery: canSubmitLottery,
                canEditSchedules: canEditSchedules,
                canManageTasks: canManageTasks,
                canManageDocuments: canManageDocuments
            )
            createdSupervisorInfo = info
            viewModel.errorMessage = nil
            // Reload data to update supervisors list
            await viewModel.loadData()
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

