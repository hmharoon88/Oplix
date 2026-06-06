//
//  ReportDateRange.swift
//  Oplix
//

import Foundation

enum ReportDateRange {
    static func interval(
        preset: ReportPeriodPreset,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = .current
    ) -> ReportDateInterval {
        let now = Date()
        switch preset {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = endOfDay(start, calendar: calendar)
            return ReportDateInterval(start: start, end: end)

        case .week:
            let weekStart = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            ) ?? calendar.startOfDay(for: now)
            return ReportDateInterval(start: weekStart, end: now)

        case .month:
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
            ) ?? calendar.startOfDay(for: now)
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
                .map { endOfDay($0, calendar: calendar) } ?? now
            return ReportDateInterval(start: monthStart, end: monthEnd)

        case .monthToDate:
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
            ) ?? calendar.startOfDay(for: now)
            return ReportDateInterval(start: monthStart, end: now)

        case .year:
            let yearStart = calendar.date(
                from: calendar.dateComponents([.year], from: now)
            ) ?? calendar.startOfDay(for: now)
            return ReportDateInterval(start: yearStart, end: now)

        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = endOfDay(customEnd, calendar: calendar)
            return ReportDateInterval(start: start, end: end)
        }
    }

    static func spanExceedsLimit(_ interval: ReportDateInterval, calendar: Calendar = .current) -> Bool {
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return days > ReportDateInterval.maxSpanDays
    }

    static func formattedRange(_ interval: ReportDateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if Calendar.current.isDate(interval.start, inSameDayAs: interval.end) {
            return formatter.string(from: interval.start)
        }
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end))"
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
