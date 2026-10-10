import Foundation

/// Tổng chi một tuần, để hiện ở tiêu đề tuần trên màn Hôm nay.
struct WeekSummary: Equatable, Sendable, Identifiable {
    var start: Date
    /// Chi trong ngân sách của tuần này (tuần đang diễn ra thì tính tới hết hôm nay).
    var total: Int
    /// Chi trong ngân sách của tuần trước: cả tuần với tuần đã qua, đúng các ngày tương ứng với tuần đang diễn ra.
    var previousTotal: Int
    /// Tuần trước có chi tiêu thì mới có gì để so.
    var hasPrevious: Bool
    var isCurrent: Bool

    var id: Date { start }
    /// Dương là chi nhiều hơn tuần trước.
    var delta: Int { total - previousTotal }
}

enum WeekSummaries {
    /// Tổng và so với tuần trước cho mọi tuần có khoản chi trong `records`. Khoản ngoài ngân sách không tính vào tổng
    /// nhưng vẫn làm tuần đó có mặt.
    static func make(records: [SpendingRecord], now: Date, calendar: Calendar) -> [Date: WeekSummary] {
        let currentStart = HistoryWindow.weekStart(of: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let elapsedDays = calendar.dateComponents([.day], from: currentStart, to: today).day ?? 0

        var inBudget: [Date: [SpendingRecord]] = [:]
        var weeks = Set<Date>()
        for record in records {
            let start = HistoryWindow.weekStart(of: record.date, calendar: calendar)
            weeks.insert(start)
            if !record.isOutsideBudget { inBudget[start, default: []].append(record) }
        }

        var result: [Date: WeekSummary] = [:]
        for start in weeks {
            let isCurrent = start == currentStart
            let previousStart = HistoryWindow.comparisonStart(for: start, calendar: calendar)
            // Tuần đang diễn ra chỉ so với các ngày tương ứng của tuần trước, không so với cả một tuần đã xong.
            let previousEnd = isCurrent
                ? min(calendar.date(byAdding: .day, value: elapsedDays + 1, to: previousStart) ?? start, start)
                : start
            let previous = (inBudget[previousStart] ?? []).filter { $0.date < previousEnd }
            result[start] = WeekSummary(
                start: start,
                total: (inBudget[start] ?? []).reduce(0) { $0 + $1.amount },
                previousTotal: previous.reduce(0) { $0 + $1.amount },
                hasPrevious: !previous.isEmpty,
                isCurrent: isCurrent
            )
        }
        return result
    }
}
