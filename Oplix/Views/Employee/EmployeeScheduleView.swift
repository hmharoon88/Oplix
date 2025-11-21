//
//  EmployeeScheduleView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI
import UIKit

struct EmployeeScheduleView: View {
    @ObservedObject var viewModel: EmployeeHomeViewModel
    
    private var upcomingShifts: [Shift] {
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        
        return viewModel.allShifts
            .filter { shift in
                // Show assigned shifts (not started) or shifts in the future
                if shift.isAssigned {
                    return true // Show all assigned shifts
                }
                if let clockInTime = shift.clockInTime {
                    return clockInTime <= nextMonth
                }
                return false
            }
            .sorted { shift1, shift2 in
                let time1 = shift1.clockInTime ?? shift1.assignedAt ?? Date.distantPast
                let time2 = shift2.clockInTime ?? shift2.assignedAt ?? Date.distantPast
                return time1 < time2
            }
    }
    
    private var shiftsByDate: [Date: [Shift]] {
        let calendar = Calendar.current
        var grouped: [Date: [Shift]] = [:]
        
        for shift in upcomingShifts {
            let date: Date
            if let clockInTime = shift.clockInTime {
                date = calendar.startOfDay(for: clockInTime)
            } else if let assignedAt = shift.assignedAt {
                date = calendar.startOfDay(for: assignedAt)
            } else {
                continue
            }
            
            if grouped[date] == nil {
                grouped[date] = []
            }
            grouped[date]?.append(shift)
        }
        
        return grouped
    }
    
    private var sortedDates: [Date] {
        shiftsByDate.keys.sorted()
    }
    
    private func dailyHours(for date: Date) -> Double {
        let calendar = Calendar.current
        guard let shifts = shiftsByDate[date] else { return 0.0 }
        
        return shifts
            .compactMap { shift -> Double? in
                // Only count completed shifts (have clockOutTime)
                if shift.clockOutTime != nil {
                    return shift.hoursWorked
                }
                return nil
            }
            .reduce(0, +)
    }
    
    private var dateRangeString: String {
        guard !sortedDates.isEmpty else { return "No upcoming shifts" }
        
        let calendar = Calendar.current
        let firstDate = sortedDates.first!
        let lastDate = sortedDates.last!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        if calendar.isDate(firstDate, inSameDayAs: lastDate) {
            return formatter.string(from: firstDate)
        } else {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "MMM d, yyyy"
            // If dates are in different years, include year
            if calendar.component(.year, from: firstDate) != calendar.component(.year, from: lastDate) {
                return "\(yearFormatter.string(from: firstDate)) - \(yearFormatter.string(from: lastDate))"
            } else {
                return "\(formatter.string(from: firstDate)) - \(formatter.string(from: lastDate))"
            }
        }
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Weekly Schedule Card
                    if let weeklySchedule = viewModel.employee?.weeklySchedule {
                        WeeklyScheduleDisplayCard(schedule: weeklySchedule)
                            .padding(.horizontal)
                    }
                    
                    // Header with Date Range
                    VStack(spacing: 8) {
                        Text("Upcoming Shifts")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        Text(dateRangeString)
                            .font(.subheadline)
                            .foregroundColor(Theme.cloudBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.cloudWhite)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    if upcomingShifts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.cloudBlue)
                            Text("No upcoming shifts scheduled")
                                .font(.subheadline)
                                .foregroundColor(Theme.cloudBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Group shifts by date
                        ForEach(sortedDates, id: \.self) { date in
                            VStack(alignment: .leading, spacing: 12) {
                                // Date header with daily hours
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(formatDate(date))
                                            .font(.headline)
                                            .foregroundColor(.black)
                                        if let shifts = shiftsByDate[date] {
                                            let hours = dailyHours(for: date)
                                            if hours > 0 {
                                                Text("\(String(format: "%.1f", hours)) hrs")
                                                    .font(.subheadline)
                                                    .foregroundColor(Theme.cloudBlue)
                                            } else {
                                                Text("Scheduled")
                                                    .font(.subheadline)
                                                    .foregroundColor(Theme.cloudBlue)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                // Shifts for this date
                                if let shifts = shiftsByDate[date] {
                                    ForEach(shifts) { shift in
                                        ScheduleShiftCard(shift: shift, viewModel: viewModel)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Schedule")
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

struct ScheduleShiftCard: View {
    let shift: Shift
    @ObservedObject var viewModel: EmployeeHomeViewModel
    
    private var timeString: String {
        if let clockInTime = shift.clockInTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: clockInTime)
        } else if let assignedAt = shift.assignedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: assignedAt)
        }
        return "TBD"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Label(timeString, systemImage: "clock.fill")
                        .font(.subheadline)
                        .foregroundColor(Theme.cloudBlue)
                    
                    if shift.isAssigned {
                        Text("Assigned")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                    } else if shift.isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(6)
                    } else if shift.isCompleted {
                        if let hours = shift.hoursWorked {
                            Text("\(String(format: "%.1f", hours)) hrs")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(6)
                        } else {
                            Text("Completed")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct WeeklyScheduleDisplayCard: View {
    let schedule: WeeklySchedule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Schedule")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.black)
            
            Text("Repeating schedule")
                .font(.caption)
                .foregroundColor(Theme.darkGray)
            
            VStack(alignment: .leading, spacing: 8) {
                DayScheduleDisplayRow(dayName: "Monday", daySchedule: schedule.monday)
                DayScheduleDisplayRow(dayName: "Tuesday", daySchedule: schedule.tuesday)
                DayScheduleDisplayRow(dayName: "Wednesday", daySchedule: schedule.wednesday)
                DayScheduleDisplayRow(dayName: "Thursday", daySchedule: schedule.thursday)
                DayScheduleDisplayRow(dayName: "Friday", daySchedule: schedule.friday)
                DayScheduleDisplayRow(dayName: "Saturday", daySchedule: schedule.saturday)
                DayScheduleDisplayRow(dayName: "Sunday", daySchedule: schedule.sunday)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct DayScheduleDisplayRow: View {
    let dayName: String
    let daySchedule: WeeklySchedule.DaySchedule?
    
    var body: some View {
        HStack {
            Text(dayName)
                .font(.subheadline)
                .foregroundColor(.black)
                .frame(width: 80, alignment: .leading)
            
            if let schedule = daySchedule, schedule.isWorking {
                Text("\(schedule.startTime) - \(schedule.endTime)")
                    .font(.subheadline)
                    .foregroundColor(Theme.cloudBlue)
            } else {
                Text("Off")
                    .font(.subheadline)
                    .foregroundColor(Theme.darkGray)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension EmployeeScheduleView {
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            formatter.dateFormat = "EEEE, MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}

