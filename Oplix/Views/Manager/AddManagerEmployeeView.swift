//
//  AddManagerEmployeeView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddManagerEmployeeView: View {
    @ObservedObject var viewModel: ManagerEmployeesViewModel
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
    @State private var selectedLocationIds: Set<String> = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var createdEmployeeInfo: (username: String, email: String, password: String)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Employee Details") {
                        TextField("Employee Name", text: $name)
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
                    
                    Section("Permissions") {
                        Toggle("Can Take Register", isOn: $canTakeRegister)
                        Toggle("Can Submit Lottery", isOn: $canSubmitLottery)
                    }
                    
                    Section("Assign to Locations (Optional)") {
                        if viewModel.locations.isEmpty {
                            Text("No locations available")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        } else {
                            ForEach(viewModel.locations) { location in
                                Toggle(location.name, isOn: Binding(
                                    get: { selectedLocationIds.contains(location.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedLocationIds.insert(location.id)
                                        } else {
                                            selectedLocationIds.remove(location.id)
                                        }
                                    }
                                ))
                            }
                        }
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
            }
            .navigationTitle("New Employee")
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
                            await createEmployee()
                        }
                    }
                    .disabled(name.isEmpty || password.isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Employee Created Successfully", isPresented: $showingSuccess) {
                Button("Copy Password") {
                    if let password = createdEmployeeInfo?.password {
                        UIPasteboard.general.string = password
                    }
                }
                Button("Done", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let info = createdEmployeeInfo {
                    Text("Email: \(info.email)\n\nPassword: \(info.password)")
                }
            }
            .task {
                await viewModel.loadData()
            }
        }
    }
    
    private var generatedUsername: String {
        guard !name.isEmpty else { return "" }
        let username = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return username.isEmpty ? "employee" : username
    }
    
    private var generatedEmail: String {
        let username = generatedUsername
        return username.isEmpty ? "" : "\(username)@oplix.app"
    }
    
    private func createEmployee() async {
        do {
            let startTime = (!useWeeklySchedule && hasWorkingHours) ? formatTime(workingHoursStart) : nil
            let endTime = (!useWeeklySchedule && hasWorkingHours) ? formatTime(workingHoursEnd) : nil
            let schedule = useWeeklySchedule ? weeklySchedule : nil
            let rate = hourlyRate.isEmpty ? nil : Double(hourlyRate)
            let assignedLocationIds = Array(selectedLocationIds)
            
            let info = try await viewModel.createEmployee(
                name: name,
                password: password,
                workingHoursStart: startTime,
                workingHoursEnd: endTime,
                weeklySchedule: schedule,
                assignedLocationIds: assignedLocationIds,
                hourlyRate: rate,
                canTakeRegister: canTakeRegister,
                canSubmitLottery: canSubmitLottery
            )
            createdEmployeeInfo = info
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

