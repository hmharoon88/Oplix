//
//  SupervisorControlsView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct SupervisorControlsView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedLocation: Location?
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if let employee = viewModel.employee, let location = viewModel.location {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.purple)
                            Text("Supervisor Controls")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            Text(location.name)
                                .font(.subheadline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .padding(.top, 20)
                        
                        // Control Cards based on permissions.
                        //
                        // Note: the "Switch Location" affordance now
                        // lives on the home screen (visible to anyone
                        // assigned to ≥ 2 locations), so it's not
                        // duplicated here.
                        VStack(spacing: 16) {
                            // Edit Employee Schedules
                            if employee.canEditSchedules == true {
                                NavigationLink(value: SupervisorControl.editSchedules) {
                                    SupervisorControlCard(
                                        icon: "calendar.badge.clock",
                                        title: "Edit Employee Schedules",
                                        description: "Change schedules for employees at this location",
                                        color: .indigo
                                    )
                                }
                            }
                            
                            // Task Check — full audit + manage. Same screen
                            // the executive sees on their Task Check tab,
                            // scoped to this location: lets the supervisor
                            // add, edit, delete tasks AND approve /
                            // disapprove employee completion photos.
                            if employee.canManageTasks == true {
                                NavigationLink(value: SupervisorControl.taskCheck) {
                                    SupervisorControlCard(
                                        icon: "checklist.checked",
                                        title: "Task Check",
                                        description: "Audit, approve photos, and manage all tasks at this location",
                                        color: .teal
                                    )
                                }
                            }
                            
                            // Manage Documents
                            if employee.canManageDocuments == true {
                                NavigationLink(value: SupervisorControl.manageDocuments) {
                                    SupervisorControlCard(
                                        icon: "doc.fill",
                                        title: "Manage Documents",
                                        description: "Add and manage documents for this location",
                                        color: .orange
                                    )
                                }
                            }
                            
                            // Payables
                            if let location = viewModel.location, let employee = viewModel.employee {
                                NavigationLink(value: SupervisorControl.payables) {
                                    SupervisorControlCard(
                                        icon: "arrow.up.circle.fill",
                                        title: "Payables",
                                        description: "View and manage payables for this location",
                                        color: .red
                                    )
                                }
                            }
                            
                            // Receivables
                            if let location = viewModel.location, let employee = viewModel.employee {
                                NavigationLink(value: SupervisorControl.receivables) {
                                    SupervisorControlCard(
                                        icon: "arrow.down.circle.fill",
                                        title: "Receivables",
                                        description: "View and manage receivables for this location",
                                        color: .blue
                                    )
                                }
                            }
                            
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(Theme.darkGray)
                }
            }
        }
        .navigationTitle("Supervise")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .navigationDestination(for: SupervisorControl.self) { control in
            switch control {
            case .editSchedules:
                if let location = viewModel.location, let employee = viewModel.employee {
                    SupervisorEditSchedulesView(managerUserId: employee.managerUserId, locationId: location.id, currentUserRole: authViewModel.currentUser?.role)
                } else {
                    Text("Error: Location not found")
                }
            case .taskCheck:
                if let location = viewModel.location, let employee = viewModel.employee {
                    // Full Task Check screen — same hub the executive sees,
                    // but scoped to this supervisor's location:
                    //   • `userId` is the manager (data root)
                    //   • `reviewerUserId` is the supervisor's auth id, so
                    //     photo approvals are attributed to them
                    //   • `allLocations: [location]` keeps create flows
                    //     single-location (the existing scope-prompt skips
                    //     itself when only one location is available)
                    TaskStatusView(
                        userId: employee.managerUserId,
                        location: location,
                        allLocations: [location],
                        reviewerUserId: authViewModel.currentUser?.id,
                        currentUserRole: authViewModel.currentUser?.role
                    )
                } else {
                    Text("Error: Location not found")
                }
            case .manageTasks:
                if let location = viewModel.location, let employee = viewModel.employee {
                    SupervisorManageTasksView(managerUserId: employee.managerUserId, locationId: location.id, currentUserRole: authViewModel.currentUser?.role)
                } else {
                    Text("Error: Location not found")
                }
            case .manageDocuments:
                if let location = viewModel.location, let employee = viewModel.employee {
                    SupervisorDocumentsWrapperView(managerUserId: employee.managerUserId, locationId: location.id, currentUserRole: authViewModel.currentUser?.role)
                } else {
                    Text("Error: Location not found")
                }
            case .payables:
                if let location = viewModel.location, let employee = viewModel.employee {
                    PayablesView(userId: employee.managerUserId, locationId: location.id)
                } else {
                    Text("Error: Location not found")
                }
            case .receivables:
                if let location = viewModel.location, let employee = viewModel.employee {
                    ReceivablesView(userId: employee.managerUserId, locationId: location.id)
                } else {
                    Text("Error: Location not found")
                }
            }
        }
    }
}

enum SupervisorControl: String, Identifiable, Hashable {
    case editSchedules, taskCheck, manageTasks, manageDocuments, payables, receivables

    var id: String { rawValue }
}

struct SupervisorControlCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(color)
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(Theme.darkGray)
                .font(.caption)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Supervisor View Schedules and Tasks View
struct SupervisorViewSchedulesAndTasksView: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    @State private var selectedTab: ViewTab = .schedules
    @EnvironmentObject var authViewModel: AuthViewModel
    
    enum ViewTab {
        case schedules, tasks
    }
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("View", selection: $selectedTab) {
                Text("Schedules").tag(ViewTab.schedules)
                Text("Tasks").tag(ViewTab.tasks)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            if selectedTab == .schedules {
                SupervisorViewSchedulesContent(managerUserId: managerUserId, locationId: locationId, currentUserRole: currentUserRole)
            } else {
                SupervisorViewTasksContent(managerUserId: managerUserId, locationId: locationId, currentUserRole: currentUserRole)
            }
        }
        .navigationTitle("View")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Supervisor View Schedules Content
struct SupervisorViewSchedulesContent: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading employees...")
                        .foregroundColor(Theme.darkGray)
                }
            } else if viewModel.employees.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Employees")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("No employees found at this location")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                }
            } else {
                List {
                    ForEach(viewModel.employees) { employee in
                        NavigationLink(value: employee) {
                            EmployeeScheduleRow(employee: employee)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: Employee.self) { employee in
                    EmployeeScheduleDetailView(employee: employee)
                }
            }
        }
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .task(id: locationId) {
            // Only load if data not loaded (allow loading even if isLoading is true initially)
            guard viewModel.location == nil || viewModel.employees.isEmpty else {
                print("⚠️ Skipping loadData - data already loaded")
                return
            }
            await viewModel.loadData()
        }
    }
}

// MARK: - Employee Schedule Row
struct EmployeeScheduleRow: View {
    let employee: Employee
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(employee.name)
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
            }
            
            if let schedule = employee.weeklySchedule {
                VStack(alignment: .leading, spacing: 8) {
                    if let monday = schedule.monday, monday.isWorking {
                        HStack {
                            Text("Mon")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(monday.startTime) - \(monday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let tuesday = schedule.tuesday, tuesday.isWorking {
                        HStack {
                            Text("Tue")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(tuesday.startTime) - \(tuesday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let wednesday = schedule.wednesday, wednesday.isWorking {
                        HStack {
                            Text("Wed")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(wednesday.startTime) - \(wednesday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let thursday = schedule.thursday, thursday.isWorking {
                        HStack {
                            Text("Thu")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(thursday.startTime) - \(thursday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let friday = schedule.friday, friday.isWorking {
                        HStack {
                            Text("Fri")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(friday.startTime) - \(friday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let saturday = schedule.saturday, saturday.isWorking {
                        HStack {
                            Text("Sat")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(saturday.startTime) - \(saturday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    if let sunday = schedule.sunday, sunday.isWorking {
                        HStack {
                            Text("Sun")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                                .frame(width: 50, alignment: .leading)
                            Text("\(sunday.startTime) - \(sunday.endTime)")
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                }
            } else if let start = employee.workingHoursStart, let end = employee.workingHoursEnd {
                HStack {
                    Text("Daily:")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                    Text("\(start) - \(end)")
                        .font(.caption)
                        .foregroundColor(.black)
                }
            } else {
                Text("No schedule set")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }
}

// MARK: - Employee Schedule Detail View
struct EmployeeScheduleDetailView: View {
    let employee: Employee
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Employee Info
                    VStack(spacing: 8) {
                        Text(employee.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        Text(employee.username)
                            .font(.subheadline)
                            .foregroundColor(Theme.darkGray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.cloudWhite)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Schedule Details
                    if let schedule = employee.weeklySchedule {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Weekly Schedule")
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal)
                            
                            ScheduleDetailRow(day: "Monday", schedule: schedule.monday)
                            ScheduleDetailRow(day: "Tuesday", schedule: schedule.tuesday)
                            ScheduleDetailRow(day: "Wednesday", schedule: schedule.wednesday)
                            ScheduleDetailRow(day: "Thursday", schedule: schedule.thursday)
                            ScheduleDetailRow(day: "Friday", schedule: schedule.friday)
                            ScheduleDetailRow(day: "Saturday", schedule: schedule.saturday)
                            ScheduleDetailRow(day: "Sunday", schedule: schedule.sunday)
                            
                            .padding(.horizontal)
                        }
                    } else if let start = employee.workingHoursStart, let end = employee.workingHoursEnd {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Working Hours")
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding(.horizontal)
                            
                            HStack {
                                Text("Daily:")
                                    .font(.body)
                                    .foregroundColor(.black)
                                Spacer()
                                Text("\(start) - \(end)")
                                    .font(.body)
                                    .foregroundColor(.black)
                            }
                            .padding()
                            .background(Theme.cloudWhite)
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 50))
                                .foregroundColor(Theme.darkGray)
                            Text("No Schedule Set")
                                .font(.title2)
                                .foregroundColor(Theme.darkGray)
                            Text("This employee does not have a schedule configured")
                                .font(.subheadline)
                                .foregroundColor(Theme.darkGray)
                        }
                        .padding()
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Schedule Detail Row
struct ScheduleDetailRow: View {
    let day: String
    let schedule: WeeklySchedule.DaySchedule?
    
    var body: some View {
        HStack {
            Text(day)
                .font(.body)
                .foregroundColor(.black)
                .frame(width: 100, alignment: .leading)
            
            if let schedule = schedule, schedule.isWorking {
                Text("\(schedule.startTime) - \(schedule.endTime)")
                    .font(.body)
                    .foregroundColor(.black)
            } else {
                Text("Off")
                    .font(.body)
                    .foregroundColor(Theme.darkGray)
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(8)
    }
}

// MARK: - Supervisor View Tasks Content
struct SupervisorViewTasksContent: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading tasks...")
                        .foregroundColor(Theme.darkGray)
                }
            } else if viewModel.tasks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "checklist")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Tasks")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("No tasks found at this location")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                }
            } else {
                List {
                    ForEach(viewModel.tasks) { task in
                        TaskDetailRow(task: task, employees: viewModel.employees)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .task(id: locationId) {
            // Only load if data not loaded (allow loading even if isLoading is true initially)
            guard viewModel.location == nil || viewModel.employees.isEmpty else {
                print("⚠️ Skipping loadData - data already loaded")
                return
            }
            await viewModel.loadData()
        }
    }
}

// MARK: - Task Detail Row
struct TaskDetailRow: View {
    let task: WorkTask
    let employees: [Employee]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: task.employeeCompletions.isEmpty ? "circle" : "checkmark.circle.fill")
                    .foregroundColor(task.employeeCompletions.isEmpty ? Theme.darkGray : .green)
                    .font(.title3)
                
                Text(task.description)
                    .font(.body)
                    .foregroundColor(.black)
                    .strikethrough(!task.employeeCompletions.isEmpty)
                
                Spacer()
            }
            
            if !task.assignedEmployeeIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assigned to:")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                    
                    ForEach(task.assignedEmployeeIds, id: \.self) { employeeId in
                        if let employee = employees.first(where: { $0.id == employeeId }) {
                            HStack {
                                Circle()
                                    .fill(task.isCompletedBy(employeeId: employeeId) ? Color.green : Theme.darkGray)
                                    .frame(width: 8, height: 8)
                                Text(employee.name)
                                    .font(.caption)
                                    .foregroundColor(.black)
                                
                                if task.isCompletedBy(employeeId: employeeId) {
                                    Text("✓ Completed")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 32)
            } else {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                    .padding(.leading, 32)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
    }
}

// MARK: - Supervisor Edit Schedules View
struct SupervisorEditSchedulesView: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    @State private var selectedEmployee: Employee?
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading employees...")
                        .foregroundColor(Theme.darkGray)
                }
            } else if viewModel.employees.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.darkGray)
                    Text("No Employees")
                        .font(.title2)
                        .foregroundColor(Theme.darkGray)
                    Text("No employees found at this location")
                        .font(.subheadline)
                        .foregroundColor(Theme.darkGray)
                }
            } else {
                List {
                    ForEach(viewModel.employees) { employee in
                        NavigationLink(value: employee) {
                            EmployeeRow(employee: employee)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: Employee.self) { employee in
                    EmployeeDetailView(employee: employee, viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Edit Schedules")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .task(id: locationId) {
            // Only load if data not loaded (allow loading even if isLoading is true initially)
            guard viewModel.location == nil || viewModel.employees.isEmpty else {
                print("⚠️ Skipping loadData - data already loaded")
                return
            }
            await viewModel.loadData()
        }
    }
}

// MARK: - Supervisor Manage Tasks View
struct SupervisorManageTasksView: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    @State private var showingAddTask = false
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading tasks...")
                        .foregroundColor(Theme.darkGray)
                }
            } else {
                List {
                    ForEach(viewModel.tasks) { task in
                        SupervisorTaskRow(task: task)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        showingAddTask = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Task")
                        }
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Manage Tasks")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            appearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.cloudBlue)]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskView(viewModel: viewModel)
        }
        .task(id: locationId) {
            // Only load if data not loaded (allow loading even if isLoading is true initially)
            guard viewModel.location == nil || viewModel.employees.isEmpty else {
                print("⚠️ Skipping loadData - data already loaded")
                return
            }
            await viewModel.loadData()
        }
    }
}


// MARK: - Helper Views
struct SupervisorTaskRow: View {
    let task: WorkTask
    
    var body: some View {
        HStack {
            Image(systemName: "checklist")
                .foregroundColor(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.description)
                    .font(.body)
                    .foregroundColor(.black)
                Text("\(task.assignedEmployeeIds.count) employee(s) assigned")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Supervisor Documents Wrapper View
struct SupervisorDocumentsWrapperView: View {
    let managerUserId: String
    let locationId: String
    let currentUserRole: User.UserRole?
    @StateObject private var viewModel: LocationDetailViewModel
    
    init(managerUserId: String, locationId: String, currentUserRole: User.UserRole?) {
        self.managerUserId = managerUserId
        self.locationId = locationId
        self.currentUserRole = currentUserRole
        _viewModel = StateObject(wrappedValue: LocationDetailViewModel(userId: managerUserId, locationId: locationId, currentUserRole: currentUserRole))
    }
    
    var body: some View {
        DocumentsScreen(viewModel: viewModel)
            .task(id: locationId) {
                // Only load if data not loaded
                guard viewModel.location == nil || viewModel.documents.isEmpty else {
                    print("⚠️ Skipping loadData - data already loaded")
                    return
                }
                await viewModel.loadData()
            }
    }
}

