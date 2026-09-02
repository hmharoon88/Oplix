//
//  FacilityNotificationSettings.swift
//  Oplix
//
//  Per-facility Needs Attention settings — mirrors web
//  `docs/js/facility-notification-model.js` (`notificationSettings` on the location doc).
//

import Foundation

enum FacilityNotificationType: String, CaseIterable, Identifiable, Codable {
    case clockOut = "clock_out"
    case missingRegister = "missing_register"
    case scheduleGaps = "schedule_gaps"
    case registerVariance = "register_variance"
    case lotteryNotClosed = "lottery_not_closed"
    case lotteryVariance = "lottery_variance"
    case payablesOverdue = "payables_overdue"
    case receivablesOverdue = "receivables_overdue"
    case documentExpiry = "document_expiry"
    case profileExpiry = "profile_expiry"
    case complianceExpiry = "compliance_expiry"
    case tasksRework = "tasks_rework"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clockOut: return "Employee forgot to clock out"
        case .missingRegister: return "Register data missing after shift"
        case .scheduleGaps: return "Employee with no shifts this week"
        case .registerVariance: return "Register over / short"
        case .lotteryNotClosed: return "Lottery not closed yesterday"
        case .lotteryVariance: return "Lottery over / short"
        case .payablesOverdue: return "Overdue payables"
        case .receivablesOverdue: return "Overdue receivables"
        case .documentExpiry: return "Document expiring soon"
        case .profileExpiry: return "Lease & license expiry"
        case .complianceExpiry: return "Compliance licenses & permits"
        case .tasksRework: return "Tasks need rework"
        }
    }

    var group: String {
        switch self {
        case .clockOut, .missingRegister, .scheduleGaps:
            return "Shifts & staffing"
        case .registerVariance, .lotteryNotClosed, .lotteryVariance:
            return "Sales & lottery"
        case .payablesOverdue, .receivablesOverdue:
            return "Finance"
        case .documentExpiry, .profileExpiry, .complianceExpiry:
            return "Compliance"
        case .tasksRework:
            return "Operations"
        }
    }

    var hasLeadDays: Bool {
        switch self {
        case .documentExpiry, .profileExpiry, .complianceExpiry:
            return true
        default:
            return false
        }
    }

    var defaultLeadDays: Int {
        switch self {
        case .documentExpiry: return 30
        case .profileExpiry: return 60
        case .complianceExpiry: return 60
        default: return 0
        }
    }
}

struct FacilityNotificationItem: Codable, Equatable {
    var enabled: Bool = true
    var leadDays: Int?

    enum CodingKeys: String, CodingKey {
        case enabled
        case leadDays
    }
}

struct FacilityNotificationSettings: Codable, Equatable {
    var version: Int = 1
    var items: [String: FacilityNotificationItem] = [:]

    static func normalized(_ raw: FacilityNotificationSettings?) -> FacilityNotificationSettings {
        var base = FacilityNotificationSettings()
        let savedItems = raw?.items ?? [:]
        for type in FacilityNotificationType.allCases {
            base.items[type.rawValue] = normalizedItem(type: type, raw: savedItems[type.rawValue])
        }
        if let version = raw?.version {
            base.version = version
        }
        return base
    }

    private static func normalizedItem(type: FacilityNotificationType, raw: FacilityNotificationItem?) -> FacilityNotificationItem {
        var item = FacilityNotificationItem(enabled: raw?.enabled ?? true)
        if type.hasLeadDays {
            let saved = raw?.leadDays
            item.leadDays = (saved != nil && saved! >= 0) ? saved : type.defaultLeadDays
        }
        return item
    }

    func isEnabled(_ type: FacilityNotificationType) -> Bool {
        Self.normalized(self).items[type.rawValue]?.enabled ?? true
    }

    func leadDays(for type: FacilityNotificationType) -> Int? {
        guard type.hasLeadDays else { return nil }
        return Self.normalized(self).items[type.rawValue]?.leadDays ?? type.defaultLeadDays
    }

    mutating func setEnabled(_ type: FacilityNotificationType, enabled: Bool) {
        var item = items[type.rawValue] ?? FacilityNotificationItem()
        item.enabled = enabled
        items[type.rawValue] = item
    }

    mutating func setLeadDays(_ type: FacilityNotificationType, days: Int) {
        guard type.hasLeadDays else { return }
        var item = items[type.rawValue] ?? FacilityNotificationItem()
        item.leadDays = max(0, days)
        items[type.rawValue] = item
    }
}

extension ManagerAlertCategory {
    var facilityNotificationType: FacilityNotificationType? {
        switch self {
        case .forgotClockOut: return .clockOut
        case .missingRegister: return .missingRegister
        case .cashVariance: return .registerVariance
        case .lotteryNotClosed: return .lotteryNotClosed
        case .lotteryVariance: return .lotteryVariance
        case .disapprovedTasks: return .tasksRework
        case .overduePayables: return .payablesOverdue
        case .overdueReceivables: return .receivablesOverdue
        case .expiringDocs: return .documentExpiry
        case .scheduleGaps: return .scheduleGaps
        }
    }
}

extension Location {
    var effectiveNotificationSettings: FacilityNotificationSettings {
        FacilityNotificationSettings.normalized(notificationSettings)
    }

    func isNotificationEnabled(for category: ManagerAlertCategory) -> Bool {
        guard let type = category.facilityNotificationType else { return true }
        return effectiveNotificationSettings.isEnabled(type)
    }

    func isNotificationEnabled(_ type: FacilityNotificationType) -> Bool {
        effectiveNotificationSettings.isEnabled(type)
    }

    func documentExpiryLeadDays() -> Int {
        effectiveNotificationSettings.leadDays(for: .documentExpiry) ?? 30
    }

    /// Preserve all fields when applying partial updates.
    init(
        copying base: Location,
        name: String? = nil,
        address: String? = nil,
        employees: [String]? = nil,
        tasks: [String]? = nil,
        lotteryForms: [String]? = nil,
        lotteryTerminalCount: Int?? = nil,
        lotteryArchivedTerminals: [Int]?? = nil,
        lotteryScanOnly: Bool?? = nil,
        facilityType: String?? = nil,
        notificationSettings: FacilityNotificationSettings? = nil
    ) {
        id = base.id
        self.name = name ?? base.name
        self.address = address ?? base.address
        managerId = base.managerId
        self.employees = employees ?? base.employees
        self.tasks = tasks ?? base.tasks
        self.lotteryForms = lotteryForms ?? base.lotteryForms
        self.lotteryTerminalCount = lotteryTerminalCount ?? base.lotteryTerminalCount
        self.lotteryArchivedTerminals = lotteryArchivedTerminals ?? base.lotteryArchivedTerminals
        self.lotteryScanOnly = lotteryScanOnly ?? base.lotteryScanOnly
        self.facilityType = facilityType ?? base.facilityType
        self.notificationSettings = notificationSettings ?? base.notificationSettings
    }
}
