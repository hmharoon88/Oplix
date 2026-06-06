//
//  AllShiftsView.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct AllShiftsView: View {
    let userId: String
    @StateObject private var viewModel: AllShiftsViewModel
    @Environment(\.dismiss) var dismiss
    
    init(userId: String) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: AllShiftsViewModel(userId: userId))
    }
    
    private var todaysShifts: [Shift] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return viewModel.shifts.filter { shift in
            // Include shifts that:
            // 1. Are assigned but not started (clockInTime is nil)
            // 2. Were clocked in today
            // 3. Were completed today
            if shift.isAssigned {
                return true
            } else if let clockInTime = shift.clockInTime {
                if calendar.isDate(clockInTime, inSameDayAs: today) {
                    return true
                }
                if let clockOutTime = shift.clockOutTime {
                    return calendar.isDate(clockOutTime, inSameDayAs: today)
                }
                return false
            } else if let clockOutTime = shift.clockOutTime {
                return calendar.isDate(clockOutTime, inSameDayAs: today)
            }
            return false
        }.sorted { shift1, shift2 in
            // Sort: assigned first, then by clock in time
            if shift1.isAssigned && !shift2.isAssigned {
                return true
            } else if !shift1.isAssigned && shift2.isAssigned {
                return false
            }
            let time1 = shift1.clockInTime ?? Date.distantPast
            let time2 = shift2.clockInTime ?? Date.distantPast
            return time1 > time2
        }
    }
    
    private var previousShiftsByDate: [AllShiftsDateGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Filter out today's shifts
        let previousShifts = viewModel.shifts.filter { shift in
            guard let clockOutTime = shift.clockOutTime else { return false }
            return !calendar.isDate(clockOutTime, inSameDayAs: today)
        }
        
        // Group by date
        let grouped = Dictionary(grouping: previousShifts) { shift -> Date in
            guard let clockOutTime = shift.clockOutTime else { return Date() }
            return calendar.startOfDay(for: clockOutTime)
        }
        
        // Convert to AllShiftsDateGroup array and sort by date (most recent first)
        return grouped.map { date, shifts in
            AllShiftsDateGroup(date: date, shifts: shifts.sorted { shift1, shift2 in
                (shift1.clockOutTime ?? Date()) > (shift2.clockOutTime ?? Date())
            })
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Clock In/Out Data")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .task {
                    await viewModel.loadData()
                }
        }
    }
    
    private var contentView: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                scrollContent
            }
        }
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                todaysShiftsSection
                previousShiftsSection
                errorMessageView
            }
            .padding(.vertical)
        }
    }
    
    private var todaysShiftsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Shifts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Spacer()
            }
            .padding(.horizontal)
            
            if todaysShifts.isEmpty {
                emptyTodayShiftsView
            } else {
                todaysShiftsList
            }
        }
        .padding(.top)
    }
    
    private var emptyTodayShiftsView: some View {
        Text("No shifts today")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.cloudWhite)
            .cornerRadius(12)
            .padding(.horizontal)
    }
    
    private var todaysShiftsList: some View {
        ForEach(todaysShifts) { shift in
            AllShiftsRow(shift: shift, viewModel: viewModel)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var previousShiftsSection: some View {
        if !previousShiftsByDate.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Previous Shifts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal)
                
                ForEach(previousShiftsByDate) { dateGroup in
                    DisclosureGroup {
                        ForEach(dateGroup.shifts) { shift in
                            AllShiftsRow(shift: shift, viewModel: viewModel)
                                .padding(.horizontal)
                        }
                    } label: {
                        AllShiftsDateGroupCard(dateGroup: dateGroup)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .padding()
        }
    }
}

struct AllShiftsRow: View {
    let shift: Shift
    @ObservedObject var viewModel: AllShiftsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Shift #\(shift.id.prefix(8))")
                            .font(.headline)
                        
                        // Flag indicators
                        if shift.shouldBeFlagged || shift.isFlaggedInHistory {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        // Auto clocked out flag
                        if shift.isAutoClockedOut {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        // Started late flag
                        if shift.startedLate {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                    }
                    
                    // Employee name with location in brackets
                    Text(viewModel.employeeNameWithLocation(for: shift))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if shift.isAssigned {
                        Text("Assigned")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    } else if shift.isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        Text("Completed")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Clock In")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if shift.startedLate {
                            Text("(Late)")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .fontWeight(.semibold)
                        }
                    }
                    if let clockInTime = shift.clockInTime {
                        Text(clockInTime, style: .time)
                            .font(.subheadline)
                    } else {
                        Text("Not started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let clockOutTime = shift.clockOutTime {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            if shift.isAutoClockedOut {
                                Text("Auto Clock Out")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("Clock Out")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text(clockOutTime, style: .time)
                            .font(.subheadline)
                            .foregroundColor(shift.isAutoClockedOut ? .red : .primary)
                    }
                } else if shift.isActive {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("In Progress")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
            }
            
            if let hoursWorked = shift.hoursWorked {
                Text("Hours: \(String(format: "%.2f", hoursWorked))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Date Group Card
struct AllShiftsDateGroupCard: View {
    let dateGroup: AllShiftsDateGroup
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: dateGroup.date)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(dateString)
                    .font(.headline)
                    .foregroundColor(.black)
                
                Label("\(dateGroup.shifts.count) shift\(dateGroup.shifts.count == 1 ? "" : "s")", systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Theme.cloudWhite)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Date Group Model
struct AllShiftsDateGroup: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let shifts: [Shift]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }
    
    static func == (lhs: AllShiftsDateGroup, rhs: AllShiftsDateGroup) -> Bool {
        lhs.date == rhs.date
    }
}

#Preview {
    AllShiftsView(userId: "test-user")
}

