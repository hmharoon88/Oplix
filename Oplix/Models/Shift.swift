//
//  Shift.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Shift: Identifiable, Codable, Equatable {
    let id: String
    let employeeId: String
    let locationId: String
    var clockInTime: Date? // nil means assigned but not started
    var clockOutTime: Date?
    var assignedAt: Date? // When the shift was assigned (for tracking unstarted shifts)
    var acknowledged: Bool = false // Whether manager has acknowledged this flagged shift
    var scheduledStartTime: Date? // When the shift was scheduled to start (based on working hours)
    var scheduledEndTime: Date? // When the shift was scheduled to end (based on working hours)
    var isAutoClockedOut: Bool = false // Whether the shift was auto clocked out by the system
    var startedLate: Bool = false // Whether the employee started the shift late
    var manuallyClockedOut: Bool = true // Whether the employee manually clocked out (false if auto)
    
    // Register fields
    var cashSale: Double?
    var cashInHand: Double?
    var overShort: Double?
    var creditCard: Double?
    var expenses: [Expense] = [] // Expenses added by employee
    
    // Custom decoding to handle missing fields in existing Firestore documents
    enum CodingKeys: String, CodingKey {
        case id
        case employeeId
        case locationId
        case clockInTime
        case clockOutTime
        case assignedAt
        case acknowledged
        case scheduledStartTime
        case scheduledEndTime
        case isAutoClockedOut
        case startedLate
        case manuallyClockedOut
        case cashSale
        case cashInHand
        case overShort
        case creditCard
        case expenses
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        employeeId = try container.decode(String.self, forKey: .employeeId)
        locationId = try container.decode(String.self, forKey: .locationId)
        clockInTime = try container.decodeIfPresent(Date.self, forKey: .clockInTime)
        clockOutTime = try container.decodeIfPresent(Date.self, forKey: .clockOutTime)
        assignedAt = try container.decodeIfPresent(Date.self, forKey: .assignedAt)
        acknowledged = try container.decodeIfPresent(Bool.self, forKey: .acknowledged) ?? false
        scheduledStartTime = try container.decodeIfPresent(Date.self, forKey: .scheduledStartTime)
        scheduledEndTime = try container.decodeIfPresent(Date.self, forKey: .scheduledEndTime)
        isAutoClockedOut = try container.decodeIfPresent(Bool.self, forKey: .isAutoClockedOut) ?? false
        startedLate = try container.decodeIfPresent(Bool.self, forKey: .startedLate) ?? false
        manuallyClockedOut = try container.decodeIfPresent(Bool.self, forKey: .manuallyClockedOut) ?? true
        cashSale = try container.decodeIfPresent(Double.self, forKey: .cashSale)
        cashInHand = try container.decodeIfPresent(Double.self, forKey: .cashInHand)
        overShort = try container.decodeIfPresent(Double.self, forKey: .overShort)
        creditCard = try container.decodeIfPresent(Double.self, forKey: .creditCard)
        expenses = try container.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(employeeId, forKey: .employeeId)
        try container.encode(locationId, forKey: .locationId)
        try container.encodeIfPresent(clockInTime, forKey: .clockInTime)
        try container.encodeIfPresent(clockOutTime, forKey: .clockOutTime)
        try container.encodeIfPresent(assignedAt, forKey: .assignedAt)
        try container.encode(acknowledged, forKey: .acknowledged)
        try container.encodeIfPresent(scheduledStartTime, forKey: .scheduledStartTime)
        try container.encodeIfPresent(scheduledEndTime, forKey: .scheduledEndTime)
        try container.encode(isAutoClockedOut, forKey: .isAutoClockedOut)
        try container.encode(startedLate, forKey: .startedLate)
        try container.encode(manuallyClockedOut, forKey: .manuallyClockedOut)
        try container.encodeIfPresent(cashSale, forKey: .cashSale)
        try container.encodeIfPresent(cashInHand, forKey: .cashInHand)
        try container.encodeIfPresent(overShort, forKey: .overShort)
        try container.encodeIfPresent(creditCard, forKey: .creditCard)
        try container.encode(expenses, forKey: .expenses)
    }
    
    // Initializer for creating new shifts
    init(id: String, employeeId: String, locationId: String, clockInTime: Date? = nil, clockOutTime: Date? = nil, assignedAt: Date? = nil, acknowledged: Bool = false, scheduledStartTime: Date? = nil, scheduledEndTime: Date? = nil, isAutoClockedOut: Bool = false, startedLate: Bool = false, manuallyClockedOut: Bool = true, cashSale: Double? = nil, cashInHand: Double? = nil, overShort: Double? = nil, creditCard: Double? = nil, expenses: [Expense] = []) {
        self.id = id
        self.employeeId = employeeId
        self.locationId = locationId
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.assignedAt = assignedAt
        self.acknowledged = acknowledged
        self.scheduledStartTime = scheduledStartTime
        self.scheduledEndTime = scheduledEndTime
        self.isAutoClockedOut = isAutoClockedOut
        self.startedLate = startedLate
        self.manuallyClockedOut = manuallyClockedOut
        self.cashSale = cashSale
        self.cashInHand = cashInHand
        self.overShort = overShort
        self.creditCard = creditCard
        self.expenses = expenses
    }
    
    var isAssigned: Bool {
        return clockInTime == nil
    }
    
    var isActive: Bool {
        return clockInTime != nil && clockOutTime == nil
    }
    
    var isCompleted: Bool {
        return clockOutTime != nil
    }
    
    // Check if shift should be flagged (assigned but not started and not acknowledged)
    var shouldBeFlagged: Bool {
        guard isAssigned, let assignedAt = assignedAt else { return false }
        // Flag if assigned more than 24 hours ago and not acknowledged
        let hoursSinceAssigned = Date().timeIntervalSince(assignedAt) / 3600.0
        return hoursSinceAssigned >= 24 && !acknowledged
    }
    
    // Check if shift is flagged in history (was assigned but took too long to start)
    var isFlaggedInHistory: Bool {
        guard let assignedAt = assignedAt else { return false }
        
        // If still assigned (never started), check if it should be flagged
        if isAssigned {
            let hoursSinceAssigned = Date().timeIntervalSince(assignedAt) / 3600.0
            return hoursSinceAssigned >= 24 && !acknowledged
        }
        
        // If completed, check if it took too long to start
        if isCompleted, let clockInTime = clockInTime {
            let hoursToStart = clockInTime.timeIntervalSince(assignedAt) / 3600.0
            return hoursToStart >= 24 && !acknowledged
        }
        
        return false
    }
    
    var duration: TimeInterval? {
        guard let clockInTime = clockInTime,
              let clockOutTime = clockOutTime else { return nil }
        return clockOutTime.timeIntervalSince(clockInTime)
    }
    
    var hoursWorked: Double? {
        guard let clockInTime = clockInTime else { return nil }
        
        // If auto clocked out, use scheduled end time instead of actual clock out time
        let endTime: Date
        if isAutoClockedOut, let scheduledEnd = scheduledEndTime {
            endTime = scheduledEnd
        } else if let clockOut = clockOutTime {
            endTime = clockOut
        } else {
            return nil
        }
        
        // Calculate hours and ensure it's not negative (safeguard against data issues)
        let hours = endTime.timeIntervalSince(clockInTime) / 3600.0
        return hours > 0 ? hours : nil
    }
    
    // Check if shift started late (after scheduled start time)
    var isStartedLate: Bool {
        guard let clockInTime = clockInTime,
              let scheduledStart = scheduledStartTime else { return false }
        return clockInTime > scheduledStart
    }
    
    // Check if shift should be auto clocked out (10 minutes after scheduled end time)
    var shouldAutoClockOut: Bool {
        guard isActive,
              let scheduledEnd = scheduledEndTime else { return false }
        let now = Date()
        let tenMinutesAfterEnd = scheduledEnd.addingTimeInterval(600) // 10 minutes = 600 seconds
        return now >= tenMinutesAfterEnd
    }
    
    var hasRegisterData: Bool {
        return cashSale != nil || cashInHand != nil || overShort != nil || creditCard != nil
    }
}

