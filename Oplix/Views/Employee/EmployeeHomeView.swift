//
//  EmployeeHomeView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeHomeView: View {
    let user: User
    @StateObject private var viewModel: EmployeeHomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab: EmployeeTab = .clockInOut
    
    init(user: User) {
        self.user = user
        // Use locationId from user, or fetch from employee's assigned locations
        // For now, require locationId for login (employee must be assigned to at least one location)
        guard let locationId = user.locationId else {
            fatalError("Employee must be assigned to at least one location to log in")
        }
        _viewModel = StateObject(wrappedValue: EmployeeHomeViewModel(employeeId: user.id, locationId: locationId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.secondaryGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Colored Header with App Logo
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                            Text("Oplix")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Logout") {
                                authViewModel.signOut()
                            }
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        }
                        
                        // Date and Location Info
                        if let location = viewModel.location {
                            VStack(spacing: 4) {
                                HStack {
                                    Text(formatDate(Date()))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text(location.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                                Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    
                    // Content Area
                    ScrollView {
                        VStack(spacing: 20) {
                            // Employee Name and Location
                            if let employee = viewModel.employee, let location = viewModel.location {
                                VStack(spacing: 8) {
                                    Text(employee.name)
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(Theme.cloudBlue)
                                        Text(location.name)
                                            .font(.subheadline)
                                            .foregroundColor(Theme.cloudBlue)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .padding(.horizontal)
                                
                                // Weekly Stats Card
                                WeeklyStatsCard(
                                    hours: viewModel.thisWeekHours,
                                    pay: viewModel.thisWeekPay
                                )
                                .padding(.horizontal)
                            }
                            
                            // Tab Buttons
                            VStack(spacing: 12) {
                                // Register Data Tab (if has permission)
                                if let employee = viewModel.employee, employee.hasRegisterPermission {
                                    NavigationLink(value: EmployeeTab.registerData) {
                                        EmployeeTabButton(
                                            icon: "cashregister.fill",
                                            title: "Register Data",
                                            color: .blue
                                        )
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // Lottery Tab (if has permission)
                                if let employee = viewModel.employee, employee.hasLotteryPermission {
                                    NavigationLink(value: EmployeeTab.lottery) {
                                        EmployeeTabButton(
                                            icon: "ticket.fill",
                                            title: "Lottery",
                                            color: .orange
                                        )
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // Clock In/Out Tab
                                NavigationLink(value: EmployeeTab.clockInOut) {
                                    EmployeeTabButton(
                                        icon: "clock.fill",
                                        title: "Clock In/Out",
                                        color: .green
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Tasks Tab
                                NavigationLink(value: EmployeeTab.tasks) {
                                    EmployeeTabButton(
                                        icon: "checklist",
                                        title: "Tasks",
                                        color: .purple
                                    )
                                }
                                .padding(.horizontal)
                                
                                // Schedule Tab
                                NavigationLink(value: EmployeeTab.schedule) {
                                    EmployeeTabButton(
                                        icon: "calendar",
                                        title: "Schedule",
                                        color: .indigo
                                    )
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical)
                        }
                        .padding(.vertical)
                    }
                    
                    // Colored Footer
                    HStack {
                        Spacer()
                        Text("© 2025 Oplix")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.6),  // Dark blue
                                Color(red: 0.15, green: 0.4, blue: 0.7)   // Medium dark blue
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Set navigation bar appearance to ensure proper text colors
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
                appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
            .task {
                await viewModel.loadData()
                viewModel.startObserving()
            }
            .navigationDestination(for: EmployeeTab.self) { tab in
                switch tab {
                case .registerData:
                    EmployeeRegisterDataView(viewModel: viewModel)
                case .lottery:
                    EmployeeLotteryView(viewModel: viewModel)
                case .clockInOut:
                    EmployeeClockInOutView(viewModel: viewModel)
                case .tasks:
                    EmployeeTasksView(viewModel: viewModel)
                case .schedule:
                    EmployeeScheduleView(viewModel: viewModel)
                }
            }
        }
    }
    
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy" // e.g., "Monday, January 15, 2025"
        return formatter.string(from: date)
    }
}

// MARK: - Employee Tab Enum
enum EmployeeTab: String, Identifiable, Hashable {
    case registerData, lottery, clockInOut, tasks, schedule
    
    var id: String { rawValue }
}

// MARK: - Weekly Stats Card
struct WeeklyStatsCard: View {
    let hours: Double
    let pay: Double
    
    var body: some View {
        HStack(spacing: 30) {
            VStack(spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                Text("\(String(format: "%.1f", hours)) hrs")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(Theme.darkGray)
                Text(formatCurrency(pay))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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

// MARK: - Employee Tab Button
struct EmployeeTabButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
            
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

// MARK: - Shift Register Entry Card
struct ShiftRegisterEntryCard: View {
    let shift: Shift
    @Binding var cashSale: String
    @Binding var cashInHand: String
    @Binding var overShort: String
    @Binding var creditCard: String
    @Binding var expenseDescriptions: [String]
    @Binding var expenseAmounts: [String]
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shift Manager")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.cloudBlue)
            
            // Register Fields
            VStack(alignment: .leading, spacing: 12) {
                Text("Register Data")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.cloudBlue)
                
                TextField("Cash Sale", text: $cashSale)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Cash In Hand", text: $cashInHand)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                
                // Over/Short - Auto-calculated (read-only)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Over/Short")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                    HStack {
                        Text(calculatedOverShort)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(calculatedOverShortValue >= 0 ? .green : .red)
                        Spacer()
                        Text("(Auto-calculated)")
                            .font(.caption2)
                            .foregroundColor(Theme.darkGray)
                            .italic()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                TextField("Credit Card", text: $creditCard)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Expenses Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Expenses")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.cloudBlue)
                    Spacer()
                    Button(action: {
                        expenseDescriptions.append("")
                        expenseAmounts.append("")
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                ForEach(Array(expenseDescriptions.indices), id: \.self) { index in
                    HStack(spacing: 12) {
                        // Description field (left)
                        TextField("Description", text: Binding(
                            get: { index < expenseDescriptions.count ? expenseDescriptions[index] : "" },
                            set: { newValue in
                                if index < expenseDescriptions.count {
                                    expenseDescriptions[index] = newValue
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        
                        // Amount field (right)
                        TextField("Amount", text: Binding(
                            get: { index < expenseAmounts.count ? expenseAmounts[index] : "" },
                            set: { newValue in
                                if index < expenseAmounts.count {
                                    expenseAmounts[index] = newValue
                                }
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        
                        // Delete button (only show if more than one row)
                        if expenseDescriptions.count > 1 {
                            Button(action: {
                                if index < expenseDescriptions.count {
                                    expenseDescriptions.remove(at: index)
                                }
                                if index < expenseAmounts.count {
                                    expenseAmounts.remove(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                // Total Expenses
                let totalExpenses = expenseAmounts.compactMap { Double($0) }.reduce(0, +)
                if totalExpenses > 0 {
                    Divider()
                    HStack {
                        Text("Total Expenses:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                        Spacer()
                        Text(formatCurrency(totalExpenses))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Save Button
            Button(action: onSave) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Register Data")
                }
                .frame(maxWidth: .infinity)
                .cloudButton(backgroundColor: .green)
            }
        }
        .padding()
        .cloudCard()
    }
    
    private var calculatedOverShort: String {
        let sale = Double(cashSale) ?? 0.0
        let inHand = Double(cashInHand) ?? 0.0
        let calculated = inHand - sale
        return formatCurrency(calculated)
    }
    
    private var calculatedOverShortValue: Double {
        let sale = Double(cashSale) ?? 0.0
        let inHand = Double(cashInHand) ?? 0.0
        return inHand - sale
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

struct ClockInOutCard: View {
    let employee: Employee
    let location: Location?
    let currentShift: Shift?
    let onClockIn: () -> Void
    let onClockOut: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Working Hours Info (if set)
            if let startTime = employee.workingHoursStart, let endTime = employee.workingHoursEnd {
                VStack(spacing: 4) {
                    Text("Working Hours")
                        .font(.caption)
                        .foregroundColor(Theme.darkGray)
                    HStack(spacing: 8) {
                        Text(startTime)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                        Text("-")
                            .font(.subheadline)
                            .foregroundColor(Theme.darkGray)
                        Text(endTime)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 8)
            }
            
            if let shift = currentShift {
                if shift.isActive {
                    // Shift is active (clocked in) - Show Clock Out
                    VStack(spacing: 8) {
                        Text("Clocked In")
                            .font(.headline)
                            .foregroundColor(.black)
                        if let clockInTime = shift.clockInTime {
                            Text(clockInTime, style: .time)
                                .font(.title2)
                                .foregroundColor(.black)
                        }
                        
                        // Show duration if available
                        if let hoursWorked = shift.hoursWorked {
                            Text("Duration: \(String(format: "%.1f", hoursWorked)) hours")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                        
                        Button(action: onClockOut) {
                            Text("Clock Out")
                                .frame(maxWidth: .infinity)
                                .cloudButton(backgroundColor: .red)
                        }
                    }
                } else if shift.isCompleted {
                    // Shift is completed - Show read-only info
                    VStack(spacing: 8) {
                        Text("Shift Completed")
                            .font(.headline)
                            .foregroundColor(.black)
                        if let clockInTime = shift.clockInTime, let clockOutTime = shift.clockOutTime {
                            VStack(spacing: 4) {
                                HStack {
                                    Text("In:")
                                        .font(.caption)
                                        .foregroundColor(Theme.darkGray)
                                    Text(clockInTime, style: .time)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                }
                                HStack {
                                    Text("Out:")
                                        .font(.caption)
                                        .foregroundColor(Theme.darkGray)
                                    Text(clockOutTime, style: .time)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        if let hoursWorked = shift.hoursWorked {
                            Text("Total: \(String(format: "%.1f", hoursWorked)) hours")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                    }
                } else {
                    // Shift is assigned but not started - Show Clock In
                    Button(action: onClockIn) {
                        Text("Clock In")
                            .frame(maxWidth: .infinity)
                            .cloudButton()
                    }
                }
            } else {
                // No shift - Show Clock In
                Button(action: onClockIn) {
                    Text("Clock In")
                        .frame(maxWidth: .infinity)
                        .cloudButton()
                }
            }
        }
        .padding()
        .cloudCard()
        .padding(.horizontal)
    }
}

struct TaskCard: View {
    let task: WorkTask
    let employee: Employee
    let onComplete: () -> Void
    
    @State private var previewImage: UIImage?
    
    private var isCompleted: Bool {
        task.isCompletedBy(employeeId: employee.id)
    }
    
    private var completion: TaskCompletion? {
        task.getCompletion(for: employee.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: {
                    if !isCompleted {
                        onComplete()
                    }
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isCompleted ? .green : Theme.darkGray)
                        .font(.title2)
                }
                .disabled(isCompleted)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.description)
                            .font(.body)
                            .strikethrough(isCompleted)
                            .foregroundColor(isCompleted ? Theme.darkGray : .black)
                        
                        if isCompleted {
                            Text("DONE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                    }
                    
                    if let completion = completion {
                        Text("Completed: \(completion.timestamp, style: .date) at \(completion.timestamp, style: .time)")
                            .font(.caption2)
                            .foregroundColor(Theme.darkGray)
                    }
                }
                
                Spacer()
            }
            
            // Preview image section
            if isCompleted, let completion = completion {
                HStack(spacing: 12) {
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "photo.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Photo submitted")
                                .font(.caption)
                                .foregroundColor(Theme.darkGray)
                        }
                        
                        Text("Tap to view full image")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                .onTapGesture {
                    // Could open full image view here if needed
                }
                .task {
                    await loadPreviewImage(from: completion.imageURL)
                }
            }
        }
        .padding()
        .cloudCard()
    }
    
    private func loadPreviewImage(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    previewImage = image
                }
            }
        } catch {
            print("Failed to load preview image: \(error)")
        }
    }
}

#Preview {
    EmployeeHomeView(user: User(
        id: "test",
        username: "testuser",
        role: .employee,
        locationId: "loc1",
        managerUserId: "manager1",
        createdAt: Date()
    ))
    .environmentObject(AuthViewModel())
}
