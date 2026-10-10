import Foundation

/// Cửa sổ các ngày màn Hôm nay đang tải. Luôn bắt đầu ở đầu một tuần, để mỗi tuần hiện ra trọn vẹn và tổng tuần đúng.
enum HistoryWindow {
    /// Số khoản tối đa mỗi lần tải thêm khi cuộn tới cuối.
    static let pageSize = 80
    /// Lúc đầu tải tuần này và bốn tuần trước đó.
    static let initialWeeks = 4

    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Đầu cửa sổ lúc mở màn hình: bốn tuần trước, và luôn phủ cả tháng hiện tại để tính ngân sách tháng.
    static func initialStart(now: Date, calendar: Calendar) -> Date {
        let back = calendar.date(byAdding: .weekOfYear, value: -initialWeeks, to: now) ?? now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return min(weekStart(of: back, calendar: calendar), weekStart(of: monthStart, calendar: calendar))
    }

    /// Tuần liền trước `start`. Truy vấn tải thêm tuần này để so tuần cũ nhất đang hiện với tuần trước nó.
    static func comparisonStart(for start: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
    }

    /// Đầu cửa sổ sau khi tải thêm một trang. `olderDates` là ngày các khoản cũ hơn `currentStart` (một trang, mới nhất trước).
    /// Nil khi không còn gì cũ hơn.
    static func nextStart(olderDates: [Date], currentStart: Date, calendar: Calendar) -> Date? {
        guard let oldest = olderDates.min() else { return nil }
        let start = weekStart(of: oldest, calendar: calendar)
        return start < currentStart ? start : comparisonStart(for: currentStart, calendar: calendar)
    }

    /// Đầu cửa sổ cần có để hiện được `day` (kéo dải ngày tới một ngày chưa tải).
    static func start(including day: Date, currentStart: Date, calendar: Calendar) -> Date {
        min(currentStart, weekStart(of: day, calendar: calendar))
    }
}
