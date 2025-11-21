//
//  WeeklySchedule.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct WeeklySchedule: Codable, Hashable {
    var monday: DaySchedule?
    var tuesday: DaySchedule?
    var wednesday: DaySchedule?
    var thursday: DaySchedule?
    var friday: DaySchedule?
    var saturday: DaySchedule?
    var sunday: DaySchedule?
    
    init(monday: DaySchedule? = nil, tuesday: DaySchedule? = nil, wednesday: DaySchedule? = nil, thursday: DaySchedule? = nil, friday: DaySchedule? = nil, saturday: DaySchedule? = nil, sunday: DaySchedule? = nil) {
        self.monday = monday
        self.tuesday = tuesday
        self.wednesday = wednesday
        self.thursday = thursday
        self.friday = friday
        self.saturday = saturday
        self.sunday = sunday
    }
    
    struct DaySchedule: Codable, Hashable {
        var startTime: String // "HH:mm" format (e.g., "09:00")
        var endTime: String // "HH:mm" format (e.g., "17:00")
        var isWorking: Bool = true // Whether employee works on this day
        
        init(startTime: String, endTime: String, isWorking: Bool = true) {
            self.startTime = startTime
            self.endTime = endTime
            self.isWorking = isWorking
        }
    }
    
    // Get schedule for a specific day of week (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
    func schedule(for weekday: Int) -> DaySchedule? {
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return nil
        }
    }
    
    // Get schedule for a specific date
    func schedule(for date: Date) -> DaySchedule? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        return schedule(for: weekday)
    }
    
    // Check if employee works on a specific date
    func worksOn(date: Date) -> Bool {
        guard let daySchedule = schedule(for: date) else { return false }
        return daySchedule.isWorking
    }
    
    // Get start and end times for a specific date
    func times(for date: Date) -> (start: String, end: String)? {
        guard let daySchedule = schedule(for: date), daySchedule.isWorking else { return nil }
        return (daySchedule.startTime, daySchedule.endTime)
    }
}

