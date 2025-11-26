//
//  EmployeeClockInOutView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeClockInOutView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    
    private var todayHours: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let now = Date()
        
        // Filter to today's shifts and remove duplicates by ID
        let filteredShifts = viewModel.allShifts.filter { shift in
            guard let clockInTime = shift.clockInTime else { return false }
            return clockInTime >= today && clockInTime < tomorrow
        }
        
        // Remove duplicates by ID (keep most recent)
        var uniqueShifts: [Shift] = []
        var seenIds = Set<String>()
        for shift in filteredShifts.sorted(by: { shift1, shift2 in
            guard let time1 = shift1.clockInTime, let time2 = shift2.clockInTime else { return false }
            return time1 > time2
        }) {
            if !seenIds.contains(shift.id) {
                uniqueShifts.append(shift)
                seenIds.insert(shift.id)
            }
        }
        
        let todayShifts = uniqueShifts
        
        var totalHours: Double = 0
        var processedShiftIds = Set<String>()
        
        for shift in todayShifts {
            // Skip if we've already processed this shift (duplicate check)
            guard !processedShiftIds.contains(shift.id) else { continue }
            processedShiftIds.insert(shift.id)
            
            if shift.isCompleted {
                // For completed shifts, use hoursWorked (which handles auto clock-out correctly)
                if let hours = shift.hoursWorked, hours > 0 {
                    totalHours += hours
                }
            } else if shift.isActive, let clockInTime = shift.clockInTime {
                // For active shifts, calculate from clock in time to now
                let hours = now.timeIntervalSince(clockInTime) / 3600.0
                if hours > 0 {
                    totalHours += hours
                }
            }
        }
        
        return max(0, totalHours) // Ensure non-negative
    }
    
    private var todayShiftsCompleted: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        
        return viewModel.allShifts
            .filter { shift in
                guard let clockInTime = shift.clockInTime else { return false }
                return clockInTime >= today && clockInTime < tomorrow && shift.isCompleted
            }
            .count
    }
    
    private var todayShiftsTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        
        return viewModel.allShifts
            .filter { shift in
                guard let clockInTime = shift.clockInTime else { return false }
                return clockInTime >= today && clockInTime < tomorrow
            }
            .count
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Today's Hours Card
                    VStack(spacing: 8) {
                        Text("Today's Hours")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        Text("\(String(format: "%.1f", todayHours)) hrs")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.cloudBlue)
                        
                        if todayShiftsTotal > 0 {
                            Text("\(todayShiftsCompleted) of \(todayShiftsTotal) shift\(todayShiftsTotal == 1 ? "" : "s") completed")
                                .font(.subheadline)
                                .foregroundColor(todayShiftsCompleted == todayShiftsTotal ? .green : Theme.cloudBlue)
                        } else {
                            Text("No shifts today")
                                .font(.subheadline)
                                .foregroundColor(Theme.cloudBlue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.cloudWhite)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    if let employee = viewModel.employee {
                        let clockInAction: () -> Void = {
                            Task { @MainActor in
                                viewModel.errorMessage = nil // Clear any previous errors
                                await viewModel.clockIn()
                            }
                        }
                        let clockOutAction: () -> Void = {
                            Task { @MainActor in
                                viewModel.errorMessage = nil // Clear any previous errors
                                await viewModel.clockOut()
                            }
                        }
                        ClockInOutCard(
                            employee: employee,
                            location: viewModel.location,
                            currentShift: viewModel.currentShift,
                            onClockIn: clockInAction,
                            onClockOut: clockOutAction
                        )
                        .padding(.horizontal)
                    }
                    
                    // Error message display
                    if let errorMessage = viewModel.errorMessage {
                        HStack {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Spacer()
                            Button(action: {
                                viewModel.errorMessage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Clock In/Out")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Configure navigation bar appearance for visible text
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

