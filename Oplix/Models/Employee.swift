//
//  Employee.swift
//  Oplix
//
//  Created by Hafiz Afzal on 11/17/25.
//

import Foundation

struct Employee: Identifiable, Codable, Hashable {
    let id: String
    var name: String // Allow name to be edited
    let username: String
    var locationId: String? // Optional - nil means manager-level employee, not assigned to location yet
    var assignedLocationIds: [String] // Can be assigned to multiple locations
    let managerUserId: String // Manager who owns this employee
    var password: String? // Password set by manager (optional for backward compatibility)
    var shiftHistory: [String] // Shift IDs
    var currentShiftStatus: ShiftStatus
    var workingHoursStart: String? // Working hours start time in "HH:mm" format (e.g., "09:00") - DEPRECATED: Use weeklySchedule instead
    var workingHoursEnd: String? // Working hours end time in "HH:mm" format (e.g., "17:00") - DEPRECATED: Use weeklySchedule instead
    var weeklySchedule: WeeklySchedule? // Weekly schedule that repeats indefinitely
    var is24Hours: Bool? // If true, employee can clock in at any time (24/7)
    var hourlyRate: Double? // Hourly rate in currency (e.g., 25.50)
    var canTakeRegister: Bool? // Permission to access register functionality (nil = false for backward compatibility)
    var canSubmitLottery: Bool? // Permission to submit lottery forms (nil = false for backward compatibility)
    // Supervisor-specific permissions
    var canViewEmployeeData: Bool? // Permission to view employee data and shifts
    var canManageTasks: Bool? // Permission to create, assign, and manage tasks
    var canManageDocuments: Bool? // Permission to add and manage documents for the location
    var canViewRegisterData: Bool? // Permission to view register data
    var canViewLotteryData: Bool? // Permission to view lottery data
    var canEditSchedules: Bool? // Permission to edit employee schedules
    var canViewReports: Bool? // Permission to view reports and statistics
    var canManagePayroll: Bool? // Permission to run payroll for the location
    var loans: [EmployeeLoan]? // Company loans repaid through payroll deductions
    
    // Custom decoding to handle missing weeklySchedule in existing documents
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case username
        case locationId
        case assignedLocationIds
        case managerUserId
        case password
        case shiftHistory
        case currentShiftStatus
        case workingHoursStart
        case workingHoursEnd
        case weeklySchedule
        case is24Hours
        case hourlyRate
        case canTakeRegister
        case canSubmitLottery
        case canViewEmployeeData
        case canManageTasks
        case canManageDocuments
        case canViewRegisterData
        case canViewLotteryData
        case canEditSchedules
        case canViewReports
        case canManagePayroll
        case loans
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        locationId = try container.decode(String.self, forKey: .locationId)
        managerUserId = try container.decode(String.self, forKey: .managerUserId)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        shiftHistory = try container.decodeIfPresent([String].self, forKey: .shiftHistory) ?? []
        currentShiftStatus = try container.decode(ShiftStatus.self, forKey: .currentShiftStatus)
        workingHoursStart = try container.decodeIfPresent(String.self, forKey: .workingHoursStart)
        workingHoursEnd = try container.decodeIfPresent(String.self, forKey: .workingHoursEnd)
        weeklySchedule = try container.decodeIfPresent(WeeklySchedule.self, forKey: .weeklySchedule)
        is24Hours = try container.decodeIfPresent(Bool.self, forKey: .is24Hours)
        assignedLocationIds = try container.decodeIfPresent([String].self, forKey: .assignedLocationIds) ?? []
        hourlyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyRate)
        canTakeRegister = try container.decodeIfPresent(Bool.self, forKey: .canTakeRegister)
        canSubmitLottery = try container.decodeIfPresent(Bool.self, forKey: .canSubmitLottery)
        canViewEmployeeData = try container.decodeIfPresent(Bool.self, forKey: .canViewEmployeeData)
        canManageTasks = try container.decodeIfPresent(Bool.self, forKey: .canManageTasks)
        canManageDocuments = try container.decodeIfPresent(Bool.self, forKey: .canManageDocuments)
        canViewRegisterData = try container.decodeIfPresent(Bool.self, forKey: .canViewRegisterData)
        canViewLotteryData = try container.decodeIfPresent(Bool.self, forKey: .canViewLotteryData)
        canEditSchedules = try container.decodeIfPresent(Bool.self, forKey: .canEditSchedules)
        canViewReports = try container.decodeIfPresent(Bool.self, forKey: .canViewReports)
        canManagePayroll = try container.decodeIfPresent(Bool.self, forKey: .canManagePayroll)
        loans = try container.decodeIfPresent([EmployeeLoan].self, forKey: .loans)
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(username, forKey: .username)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(managerUserId, forKey: .managerUserId)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encode(shiftHistory, forKey: .shiftHistory)
        try container.encode(currentShiftStatus, forKey: .currentShiftStatus)
        try container.encodeIfPresent(workingHoursStart, forKey: .workingHoursStart)
        try container.encodeIfPresent(workingHoursEnd, forKey: .workingHoursEnd)
        try container.encodeIfPresent(weeklySchedule, forKey: .weeklySchedule)
        try container.encodeIfPresent(is24Hours, forKey: .is24Hours)
        try container.encode(assignedLocationIds, forKey: .assignedLocationIds)
        try container.encodeIfPresent(hourlyRate, forKey: .hourlyRate)
        try container.encodeIfPresent(canTakeRegister, forKey: .canTakeRegister)
        try container.encodeIfPresent(canSubmitLottery, forKey: .canSubmitLottery)
        try container.encodeIfPresent(canViewEmployeeData, forKey: .canViewEmployeeData)
        try container.encodeIfPresent(canManageTasks, forKey: .canManageTasks)
        try container.encodeIfPresent(canManageDocuments, forKey: .canManageDocuments)
        try container.encodeIfPresent(canViewRegisterData, forKey: .canViewRegisterData)
        try container.encodeIfPresent(canViewLotteryData, forKey: .canViewLotteryData)
        try container.encodeIfPresent(canEditSchedules, forKey: .canEditSchedules)
        try container.encodeIfPresent(canViewReports, forKey: .canViewReports)
        try container.encodeIfPresent(canManagePayroll, forKey: .canManagePayroll)
        try container.encodeIfPresent(loans, forKey: .loans)
    }
    
    // Initializer for creating new employees
    init(id: String, name: String, username: String, locationId: String? = nil, managerUserId: String, password: String? = nil, shiftHistory: [String] = [], currentShiftStatus: ShiftStatus = .clockedOut, workingHoursStart: String? = nil, workingHoursEnd: String? = nil, weeklySchedule: WeeklySchedule? = nil, is24Hours: Bool? = nil, assignedLocationIds: [String] = [], hourlyRate: Double? = nil, canTakeRegister: Bool? = nil, canSubmitLottery: Bool? = nil, canViewEmployeeData: Bool? = nil, canManageTasks: Bool? = nil, canManageDocuments: Bool? = nil, canViewRegisterData: Bool? = nil, canViewLotteryData: Bool? = nil, canEditSchedules: Bool? = nil, canViewReports: Bool? = nil, canManagePayroll: Bool? = nil, loans: [EmployeeLoan]? = nil) {
        self.id = id
        self.name = name
        self.username = username
        self.locationId = locationId
        self.managerUserId = managerUserId
        self.password = password
        self.shiftHistory = shiftHistory
        self.currentShiftStatus = currentShiftStatus
        self.workingHoursStart = workingHoursStart
        self.workingHoursEnd = workingHoursEnd
        self.weeklySchedule = weeklySchedule
        self.is24Hours = is24Hours
        self.assignedLocationIds = assignedLocationIds
        self.hourlyRate = hourlyRate
        self.canTakeRegister = canTakeRegister
        self.canSubmitLottery = canSubmitLottery
        self.canViewEmployeeData = canViewEmployeeData
        self.canManageTasks = canManageTasks
        self.canManageDocuments = canManageDocuments
        self.canViewRegisterData = canViewRegisterData
        self.canViewLotteryData = canViewLotteryData
        self.canEditSchedules = canEditSchedules
        self.canViewReports = canViewReports
        self.canManagePayroll = canManagePayroll
        self.loans = loans
    }
    
    var activeLoans: [EmployeeLoan] {
        (loans ?? []).filter(\.isOpen)
    }

    var totalOpenLoanBalance: Double {
        activeLoans.reduce(0) { $0 + $1.amountDue }
    }
    
    // Computed properties for easier access (defaults to false if nil)
    var hasRegisterPermission: Bool {
        return canTakeRegister ?? false
    }
    
    var hasLotteryPermission: Bool {
        return canSubmitLottery ?? false
    }
    
    // Get working hours for a specific date (from weekly schedule or fallback to old workingHoursStart/End)
    func workingHours(for date: Date) -> (start: String, end: String)? {
        // If 24/7 is enabled, return nil to allow clocking in at any time
        if is24Hours == true {
            return nil
        }
        
        // First try weekly schedule
        if let schedule = weeklySchedule, let times = schedule.times(for: date) {
            return times
        }
        // Fallback to old workingHoursStart/End
        if let start = workingHoursStart, let end = workingHoursEnd {
            return (start, end)
        }
        return nil
    }
    
    // Check if employee works on a specific date
    func worksOn(date: Date) -> Bool {
        if let schedule = weeklySchedule {
            return schedule.worksOn(date: date)
        }
        // If no weekly schedule, assume they work if workingHoursStart/End are set
        return workingHoursStart != nil && workingHoursEnd != nil
    }
    
    enum ShiftStatus: String, Codable {
        case clockedIn
        case clockedOut
    }
}

