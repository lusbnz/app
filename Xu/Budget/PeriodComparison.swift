import Foundation

enum ComparisonPeriod: String, CaseIterable, Identifiable, Sendable {
    case month, week

    var id: String { rawValue }

    /// Kỳ của `date`: cả tháng hoặc cả tuần chứa nó.
    func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: self == .month ? .month : .weekOfYear, for: date)
    }

    /// Cùng kỳ ngay trước: tháng trước hoặc tuần trước.
    func previousInterval(of date: Date, calendar: Calendar) -> DateInterval? {
        guard let current = interval(containing: date, calendar: calendar),
              let before = calendar.date(byAdding: self == .month ? .month : .weekOfYear, value: -1, to: current.start)
        else { return nil }
        return interval(containing: before, calendar: calendar)
    }
}

/// Chi của một danh mục ở kỳ này và cùng đoạn ngày của kỳ trước.
struct CategoryChange: Equatable, Sendable, Identifiable {
    var key: String
    var current: Int
    var previous: Int

    var id: String { key }
    /// Dương là chi nhiều hơn kỳ trước.
    var delta: Int { current - previous }
    /// Phần trăm thay đổi, làm tròn; nil khi kỳ trước chưa chi gì nên không có gì để so.
    var percent: Int? {
        PeriodComparison.percent(delta, of: previous)
    }
}

struct PeriodComparison: Equatable, Sendable {
    var period: ComparisonPeriod
    /// Giảm dần theo mức thay đổi tuyệt đối. Gồm cả danh mục chỉ có chi ở kỳ trước.
    var changes: [CategoryChange]
    var currentTotal: Int
    var previousTotal: Int

    var delta: Int { currentTotal - previousTotal }

    static func percent(_ delta: Int, of base: Int) -> Int? {
        guard base > 0 else { return nil }
        // Làm tròn bằng số nguyên, không đi qua Double.
        let half = delta >= 0 ? base / 2 : -base / 2
        return (delta * 100 + half) / base
    }
    var hasData: Bool { currentTotal > 0 || previousTotal > 0 }

    /// So kỳ này (tính tới hết hôm nay) với đúng đoạn ngày đó của kỳ trước, để không so tháng mới
    /// qua 10 ngày với cả một tháng đã xong. Chỉ tính khoản trong ngân sách, như các con số khác của màn Tháng.
    static func make(records: [SpendingRecord], period: ComparisonPeriod, now: Date, calendar: Calendar) -> PeriodComparison {
        guard let current = period.interval(containing: now, calendar: calendar),
              let previous = period.previousInterval(of: now, calendar: calendar)
        else { return PeriodComparison(period: period, changes: [], currentTotal: 0, previousTotal: 0) }

        let elapsedDays = calendar.dateComponents([.day], from: current.start, to: calendar.startOfDay(for: now)).day ?? 0
        let previousEnd = min(calendar.date(byAdding: .day, value: elapsedDays + 1, to: previous.start) ?? previous.end, previous.end)
        let currentEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? current.end

        var currentTotals: [String: Int] = [:]
        var previousTotals: [String: Int] = [:]
        for record in records where !record.isOutsideBudget {
            if record.date >= current.start, record.date < currentEnd {
                currentTotals[record.categoryKey, default: 0] += record.amount
            } else if record.date >= previous.start, record.date < previousEnd {
                previousTotals[record.categoryKey, default: 0] += record.amount
            }
        }
        let changes = Set(currentTotals.keys).union(previousTotals.keys)
            .map { CategoryChange(key: $0, current: currentTotals[$0] ?? 0, previous: previousTotals[$0] ?? 0) }
            .sorted { (abs($0.delta), $1.key) > (abs($1.delta), $0.key) }
        return PeriodComparison(
            period: period, changes: changes,
            currentTotal: currentTotals.values.reduce(0, +), previousTotal: previousTotals.values.reduce(0, +)
        )
    }
}
