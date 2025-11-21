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
        
        return viewModel.allShifts
            .filter { shift in
                guard let clockInTime = shift.clockInTime else { return false }
                return clockInTime >= today && clockInTime < tomorrow
            }
            .compactMap { $0.hoursWorked }
            .reduce(0, +)
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
                                await viewModel.clockIn()
                            }
                        }
                        let clockOutAction: () -> Void = {
                            Task { @MainActor in
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

