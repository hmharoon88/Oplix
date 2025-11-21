//
//  ShiftsScreen.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct ShiftsScreen: View {
    @ObservedObject var viewModel: LocationDetailViewModel
    @State private var showingAddShift = false
    @State private var shiftToDelete: Shift?
    @State private var showingDeleteConfirmation = false
    @State private var selectedDateGroup: DateGroup?
    
    private var todaysShifts: [Shift] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return viewModel.shifts.filter { shift in
            // Include shifts that:
            // 1. Are assigned but not started (clockInTime is nil)
            // 2. Were clocked in today
            // 3. Were completed today
            if shift.isAssigned {
                // Show assigned shifts (not yet started)
                return true
            } else if let clockInTime = shift.clockInTime {
                // Check if clocked in today
                if calendar.isDate(clockInTime, inSameDayAs: today) {
                    return true
                }
                // Also check if clocked out today
                if let clockOutTime = shift.clockOutTime {
                    return calendar.isDate(clockOutTime, inSameDayAs: today)
                }
                return false
            } else if let clockOutTime = shift.clockOutTime {
                // Completed today
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
            // Both assigned or both started - sort by clock in time
            let time1 = shift1.clockInTime ?? Date.distantPast
            let time2 = shift2.clockInTime ?? Date.distantPast
            return time1 > time2
        }
    }
    
    private var previousShiftsByDate: [DateGroup] {
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
        
        // Convert to DateGroup array and sort by date (most recent first)
        return grouped.map { date, shifts in
            DateGroup(date: date, shifts: shifts.sorted { shift1, shift2 in
                (shift1.clockOutTime ?? Date()) > (shift2.clockOutTime ?? Date())
            })
        }.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            Theme.secondaryGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Today's Shifts Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with Add/Delete options
                        HStack {
                            Text("Today's Shifts")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            // Add Shift Button
                            Button(action: {
                                showingAddShift = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add")
                                }
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Today's shifts list
                        if todaysShifts.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock.badge.xmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("No shifts for today")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .padding(.horizontal)
                        } else {
                            ForEach(Array(todaysShifts.enumerated()), id: \.element.id) { index, shift in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Shift number and delete button
                                    HStack {
                                        Text("Shift \(index + 1)")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                        Spacer()
                                        Button(action: {
                                            shiftToDelete = shift
                                            showingDeleteConfirmation = true
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .font(.subheadline)
                                        }
                                    }
                                    
                                    // Shift data
                                    TodayShiftDataCard(shift: shift, viewModel: viewModel)
                                }
                                .padding()
                                .background(Theme.cloudWhite)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Previous Shifts Section
                    if !previousShiftsByDate.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Previous Shifts")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal)
                            
                            ForEach(previousShiftsByDate, id: \.date) { dateGroup in
                                NavigationLink(value: dateGroup) {
                                    DateGroupCard(dateGroup: dateGroup, viewModel: viewModel)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Shift Manager")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: DateGroup.self) { dateGroup in
            ShiftDateDetailView(dateGroup: dateGroup, viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddShift) {
            AddShiftView(viewModel: viewModel)
        }
        .alert("Delete Shift", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                shiftToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let shift = shiftToDelete {
                    Task {
                        await viewModel.deleteShift(shift)
                        shiftToDelete = nil
                    }
                }
            }
        } message: {
            if let shift = shiftToDelete {
                Text("Are you sure you want to delete Shift \(shift.id.prefix(8))?")
            }
        }
    }
}

// MARK: - Today's Shift Data Card
struct TodayShiftDataCard: View {
    let shift: Shift
    @ObservedObject var viewModel: LocationDetailViewModel
    
    private var employeeName: String {
        viewModel.employees.first(where: { $0.id == shift.employeeId })?.name ?? "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Employee and Status
            HStack {
                HStack(spacing: 6) {
                    Text("Employee: \(employeeName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Flag indicators
                    if shift.shouldBeFlagged || shift.isFlaggedInHistory {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                    }
                    
                    // Auto clocked out flag
                    if shift.isAutoClockedOut {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                    }
                    
                    // Started late flag
                    if shift.startedLate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.caption2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
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
                    } else {
                        Text("Completed")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                    // Acknowledge button for flagged shifts
                    if (shift.shouldBeFlagged || shift.isFlaggedInHistory) && !shift.acknowledged {
                        Button(action: {
                            Task {
                                await viewModel.acknowledgeShift(shift)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Acknowledge")
                            }
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .cornerRadius(5)
                        }
                    }
                }
            }
            
            // Time info
            if let clockInTime = shift.clockInTime {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clock In: \(clockInTime, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if shift.startedLate {
                            Text("(Late)")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                                .fontWeight(.semibold)
                        }
                    }
                    
                    if let clockOutTime = shift.clockOutTime {
                        HStack {
                            if shift.isAutoClockedOut {
                                Text("Auto Clock Out: \(clockOutTime, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("Clock Out: \(clockOutTime, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if let scheduledEnd = shift.scheduledEndTime {
                        Text("Scheduled End: \(scheduledEnd, style: .time)")
                            .font(.caption2)
                            .foregroundColor(Theme.darkGray)
                    }
                }
            }
            
            // Sales Data Summary
            if shift.hasRegisterData {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sales")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        if let cashSale = shift.cashSale {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cash Sale")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatCurrency(cashSale))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                        
                        if let creditCard = shift.creditCard {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Credit Card")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatCurrency(creditCard))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Expenses Summary
            if !shift.expenses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expenses")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    let totalExpenses = shift.expenses.reduce(0) { $0 + $1.amount }
                    Text(formatCurrency(totalExpenses))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
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

// MARK: - Date Group Card
struct DateGroupCard: View {
    let dateGroup: DateGroup
    @ObservedObject var viewModel: LocationDetailViewModel
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: dateGroup.date)
    }
    
    private var totalSales: Double {
        dateGroup.shifts.compactMap { $0.cashSale ?? $0.creditCard }.reduce(0, +)
    }
    
    private var totalExpenses: Double {
        dateGroup.shifts.flatMap { $0.expenses }.reduce(0) { $0 + $1.amount }
    }
    
    private var hasFlaggedShifts: Bool {
        dateGroup.shifts.contains { $0.shouldBeFlagged || $0.isFlaggedInHistory }
    }
    
    private var flaggedCount: Int {
        dateGroup.shifts.filter { ($0.shouldBeFlagged || $0.isFlaggedInHistory) && !$0.acknowledged }.count
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    // Flag indicator if there are flagged shifts
                    if hasFlaggedShifts && flaggedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("\(flaggedCount)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                HStack(spacing: 16) {
                    Label("\(dateGroup.shifts.count) shift\(dateGroup.shifts.count == 1 ? "" : "s")", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if totalSales > 0 {
                        Label(formatCurrency(totalSales), systemImage: "dollarsign.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if totalExpenses > 0 {
                        Label(formatCurrency(totalExpenses), systemImage: "minus.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
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
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }
}

// MARK: - Date Group Model
struct DateGroup: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let shifts: [Shift]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }
    
    static func == (lhs: DateGroup, rhs: DateGroup) -> Bool {
        lhs.date == rhs.date
    }
}

