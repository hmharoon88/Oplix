//
//  AddEmployeeView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AddEmployeeView: View {
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
    @State private var useWeeklySchedule = true // Default to weekly schedule
    @State private var weeklySchedule = WeeklySchedule()
    @State private var is24Hours = false
    @State private var hourlyRate = ""
    @State private var canTakeRegister = false
    @State private var canSubmitLottery = false
    @State private var selectedRole: User.UserRole = .employee
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var createdEmployeeInfo: (username: String, email: String, password: String)?
    
    var body: some View {
        let _ = print("🟡 SHEET - AddEmployeeView BODY RENDER")
        let _ = print("   ViewModel location: \(viewModel.location?.name ?? "nil")")
        let _ = print("   ViewModel employees count: \(viewModel.employees.count)")
        
        return NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                Form {
                    Section("Employee Details") {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                        SecureField("Password", text: $password)
                        
                        Picker("Role", selection: $selectedRole) {
                            Text("Employee").tag(User.UserRole.employee)
                            Text("Supervisor").tag(User.UserRole.supervisor)
                        }
                    }
                    
                    Section("Schedule Settings") {
                        Toggle("24/7", isOn: $is24Hours)
                            .onChange(of: is24Hours) { _, newValue in
                                // When 24/7 is enabled, disable weekly schedule
                                if newValue {
                                    useWeeklySchedule = false
                                }
                            }
                    }
                    
                    Section("Schedule") {
                        Toggle("Set Weekly Schedule", isOn: $useWeeklySchedule)
                            .disabled(is24Hours)
                            .foregroundColor(is24Hours ? Theme.darkGray : .primary)
                            .onChange(of: useWeeklySchedule) { _, newValue in
                                // When weekly schedule is enabled, disable 24/7
                                if newValue {
                                    is24Hours = false
                                }
                            }
                        
                        if useWeeklySchedule && !is24Hours {
                            WeeklyScheduleEditor(schedule: $weeklySchedule)
                                .disabled(is24Hours)
                                .opacity(is24Hours ? 0.5 : 1.0)
                        } else if !is24Hours {
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
            .navigationTitle(selectedRole == .supervisor ? "New Supervisor" : "New Employee")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("🟡 SHEET - AddEmployeeView ON APPEAR")
                print("   ViewModel location: \(viewModel.location?.name ?? "nil")")
                print("   ViewModel employees count: \(viewModel.employees.count)")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        print("🟡 SHEET - AddEmployeeView DISMISS (Cancel)")
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
            .toolbarBackground(Theme.secondaryGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                    print("🟡 SHEET - AddEmployeeView DISMISS (Success - Done)")
                    dismiss()
                }
            } message: {
                if let info = createdEmployeeInfo {
                    Text("Email: \(info.email)\n\nPassword: \(info.password)")
                }
            }
            .onChange(of: showingSuccess) { oldValue, newValue in
                if newValue {
                    print("🟡 SHEET - AddEmployeeView - Employee created successfully")
                    if let info = createdEmployeeInfo {
                        print("   Username: \(info.username)")
                        print("   Email: \(info.email)")
                    }
                }
            }
        }
    }
    
    private var generatedUsername: String {
        guard !name.isEmpty else { return "" }
        // Convert name to lowercase, remove spaces and special characters
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
            let info = try await viewModel.createEmployee(
                name: name,
                password: password,
                role: selectedRole,
                workingHoursStart: startTime,
                workingHoursEnd: endTime,
                weeklySchedule: schedule,
                is24Hours: is24Hours ? true : nil,
                hourlyRate: rate,
                canTakeRegister: canTakeRegister,
                canSubmitLottery: canSubmitLottery
            )
            createdEmployeeInfo = info
            // Clear any error messages from viewModel (might be from loadData timing issues)
            viewModel.errorMessage = nil
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

#Preview {
    AddEmployeeView(viewModel: LocationDetailViewModel(userId: "test-user", locationId: "test-location"))
}

