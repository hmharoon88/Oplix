//
//  WeeklyScheduleEditor.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import SwiftUI

struct WeeklyScheduleEditor: View {
    @Binding var schedule: WeeklySchedule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set working hours for each day")
                .font(.caption)
                .foregroundColor(.secondary)
            
            DayScheduleRow(dayName: "Monday", daySchedule: Binding(
                get: { schedule.monday },
                set: { schedule.monday = $0 }
            ))
            
            DayScheduleRow(dayName: "Tuesday", daySchedule: Binding(
                get: { schedule.tuesday },
                set: { schedule.tuesday = $0 }
            ))
            
            DayScheduleRow(dayName: "Wednesday", daySchedule: Binding(
                get: { schedule.wednesday },
                set: { schedule.wednesday = $0 }
            ))
            
            DayScheduleRow(dayName: "Thursday", daySchedule: Binding(
                get: { schedule.thursday },
                set: { schedule.thursday = $0 }
            ))
            
            DayScheduleRow(dayName: "Friday", daySchedule: Binding(
                get: { schedule.friday },
                set: { schedule.friday = $0 }
            ))
            
            DayScheduleRow(dayName: "Saturday", daySchedule: Binding(
                get: { schedule.saturday },
                set: { schedule.saturday = $0 }
            ))
            
            DayScheduleRow(dayName: "Sunday", daySchedule: Binding(
                get: { schedule.sunday },
                set: { schedule.sunday = $0 }
            ))
        }
    }
}

struct DayScheduleRow: View {
    let dayName: String
    @Binding var daySchedule: WeeklySchedule.DaySchedule?
    
    @State private var isWorking: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    
    init(dayName: String, daySchedule: Binding<WeeklySchedule.DaySchedule?>) {
        self.dayName = dayName
        self._daySchedule = daySchedule
        
        if let schedule = daySchedule.wrappedValue {
            _isWorking = State(initialValue: schedule.isWorking)
            _startTime = State(initialValue: Self.parseTime(schedule.startTime))
            _endTime = State(initialValue: Self.parseTime(schedule.endTime))
        } else {
            _isWorking = State(initialValue: false)
            var components = DateComponents()
            components.hour = 9
            components.minute = 0
            _startTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
            components.hour = 17
            _endTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(dayName, isOn: Binding(
                get: { isWorking },
                set: { newValue in
                    isWorking = newValue
                    updateSchedule()
                }
            ))
            
            if isWorking {
                HStack {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                        .onChange(of: startTime) { _, _ in updateSchedule() }
                    
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .onChange(of: endTime) { _, _ in updateSchedule() }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateSchedule() {
        if isWorking {
            daySchedule = WeeklySchedule.DaySchedule(
                startTime: formatTime(startTime),
                endTime: formatTime(endTime),
                isWorking: true
            )
        } else {
            daySchedule = nil
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private static func parseTime(_ timeString: String) -> Date {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            var dateComponents = DateComponents()
            dateComponents.hour = 9
            dateComponents.minute = 0
            return Calendar.current.date(from: dateComponents) ?? Date()
        }
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        return Calendar.current.date(from: dateComponents) ?? Date()
    }
}

