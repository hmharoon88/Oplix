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
    @State private var selectedLocationIds: Set<String> = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var scheduleConflicts: [String: [String]] = [:] // locationId: [conflicting location names]
    
    init(employee: Employee, viewModel: ManagerEmployeesViewModel) {
        self.employee = employee
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            Form {
                    // Conflict Warning Section
                    if hasScheduleConflicts {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Schedule Conflicts Detected")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Text("Please resolve overlapping schedules before saving.")
                                        .font(.caption)
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section("Employee Details") {
                        TextField("Employee Name", text: $name)
                            .textInputAutocapitalization(.words)
                        SecureField("Password", text: $password)
                    }
                    
                    Section("Assign to Locations") {
                        if viewModel.locations.isEmpty {
                            Text("No locations available")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        } else {
                            // Show selected locations first with their schedules
                            ForEach(Array(selectedLocationIds).sorted(), id: \.self) { locationId in
                                if let location = viewModel.locations.first(where: { $0.id == locationId }) {
                                    locationScheduleRow(for: location)
                                }
                            }
                            
                            // Show unselected locations below
                            ForEach(viewModel.locations.filter { !selectedLocationIds.contains($0.id) }) { location in
                                Toggle(location.name, isOn: Binding(
                                    get: { selectedLocationIds.contains(location.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedLocationIds.insert(location.id)
                                            // Initialize schedule for this location
                                            if locationSchedules[location.id] == nil {
                                                locationSchedules[location.id] = employee.weeklySchedule ?? WeeklySchedule()
                                                locationUseWeeklySchedule[location.id] = employee.weeklySchedule != nil
                                                locationHasWorkingHours[location.id] = employee.workingHoursStart != nil && employee.workingHoursEnd != nil
                                                if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                                                    locationWorkingHoursStart[location.id] = parseTimeString(startTime)
                                                    locationWorkingHoursEnd[location.id] = parseTimeString(endTime)
                                                }
                                            }
                                            // Check for conflicts with other locations
                                            checkConflicts(for: location.id)
                                        } else {
                                            selectedLocationIds.remove(location.id)
                                            locationSchedules.removeValue(forKey: location.id)
                                            locationUseWeeklySchedule.removeValue(forKey: location.id)
                                            locationHasWorkingHours.removeValue(forKey: location.id)
                                            locationWorkingHoursStart.removeValue(forKey: location.id)
                                            locationWorkingHoursEnd.removeValue(forKey: location.id)
                                            scheduleConflicts.removeValue(forKey: location.id)
                                            // Recheck conflicts for remaining locations
                                            for remainingLocationId in selectedLocationIds {
                                                checkConflicts(for: remainingLocationId)
                                            }
                                        }
                                    }
                                ))
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
                    }
                }
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
        .task {
            await viewModel.loadData()
            loadEmployeeData()
        }
    }
    
    private var generatedEmail: String {
        return "\(employee.username)@oplix.app"
    }
    
    private func loadEmployeeData() {
        name = employee.name
        password = employee.password ?? ""
        selectedLocationIds = Set(employee.assignedLocationIds)
        canTakeRegister = employee.hasRegisterPermission
        canSubmitLottery = employee.hasLotteryPermission
        
        if let rate = employee.hourlyRate {
            hourlyRate = String(format: "%.2f", rate)
        }
        
        // Load schedules for each assigned location
        for locationId in employee.assignedLocationIds {
            if let schedule = employee.weeklySchedule {
                locationSchedules[locationId] = schedule
                locationUseWeeklySchedule[locationId] = true
            } else if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                locationHasWorkingHours[locationId] = true
                locationWorkingHoursStart[locationId] = parseTimeString(startTime)
                locationWorkingHoursEnd[locationId] = parseTimeString(endTime)
                locationUseWeeklySchedule[locationId] = false
            }
        }
        
        // Check for conflicts after loading
        for locationId in selectedLocationIds {
            checkConflicts(for: locationId)
        }
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
                    startTime = formatTime(locationWorkingHoursStart[locationId] ?? Date())
                    endTime = formatTime(locationWorkingHoursEnd[locationId] ?? Date())
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
            updatedEmployee.hourlyRate = rate
            updatedEmployee.canTakeRegister = canTakeRegister
            updatedEmployee.canSubmitLottery = canSubmitLottery
            
            try await viewModel.updateEmployee(updatedEmployee)
            
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
            Toggle(location.name, isOn: Binding(
                get: { selectedLocationIds.contains(location.id) },
                set: { isOn in
                    if isOn {
                        selectedLocationIds.insert(location.id)
                        if locationSchedules[location.id] == nil {
                            locationSchedules[location.id] = employee.weeklySchedule ?? WeeklySchedule()
                            locationUseWeeklySchedule[location.id] = employee.weeklySchedule != nil
                            locationHasWorkingHours[location.id] = employee.workingHoursStart != nil && employee.workingHoursEnd != nil
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
                        // Recheck conflicts for remaining locations
                        for remainingLocationId in selectedLocationIds {
                            checkConflicts(for: remainingLocationId)
                        }
                    }
                }
            ))
            
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
                    if let locationConflicts = scheduleConflicts[location.id], !locationConflicts.isEmpty {
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
                        checkConflicts(for: location.id)
                    }
                ))
                
                if locationUseWeeklySchedule[location.id] ?? true {
                    WeeklyScheduleEditor(schedule: Binding(
                        get: { locationSchedules[location.id] ?? WeeklySchedule() },
                        set: {
                            locationSchedules[location.id] = $0
                            checkConflicts(for: location.id)
                        }
                    ))
                } else {
                    Toggle("Set Working Hours", isOn: Binding(
                        get: { locationHasWorkingHours[location.id] ?? false },
                        set: {
                            locationHasWorkingHours[location.id] = $0
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
        !scheduleConflicts.isEmpty
    }
    
    private func checkConflicts(for locationId: String) {
        var conflicts: [String] = []
        
        guard let currentLocation = viewModel.locations.first(where: { $0.id == locationId }) else { return }
        
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

