import Foundation

/// Chi từng ngày của một tuần, cho biểu đồ cột ở màn Chi tiết tuần.
struct WeekDay: Equatable, Sendable, Identifiable {
    var day: Date
    /// Chi trong ngân sách của ngày này.
    var total: Int
    /// Ngày chưa tới thì chưa có gì để vẽ.
    var isFuture: Bool
    var isToday: Bool

    var id: Date { day }
}

enum WeekDays {
    /// Bảy ngày của tuần bắt đầu từ `weekStart`, chi trong ngân sách mỗi ngày.
    static func make(records: [SpendingRecord], weekStart: Date, now: Date, calendar: Calendar) -> [WeekDay] {
        let today = calendar.startOfDay(for: now)
        var totals: [Date: Int] = [:]
        for record in records where !record.isOutsideBudget {
            totals[calendar.startOfDay(for: record.date), default: 0] += record.amount
        }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart)) else { return nil }
            return WeekDay(day: day, total: totals[day] ?? 0, isFuture: day > today, isToday: day == today)
        }
    }

    /// Ngày dùng để so tuần này với tuần trước (`PeriodComparison`): hôm nay nếu là tuần đang diễn ra,
    /// không thì ngày cuối của tuần để so cả tuần với cả tuần trước đó.
    static func comparisonReference(weekStart: Date, now: Date, calendar: Calendar) -> Date {
        let currentStart = HistoryWindow.weekStart(of: now, calendar: calendar)
        if weekStart >= currentStart { return now }
        return calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: weekStart)) ?? now
    }
}
