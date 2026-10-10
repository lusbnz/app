import Foundation

enum SummaryKind: String, CaseIterable, Sendable {
    case week, month
}

/// Số liệu của một tuần hoặc một tháng đã qua, cho thông báo tổng kết.
struct PeriodSummary: Equatable, Sendable {
    var kind: SummaryKind
    var interval: DateInterval
    /// Chi trong ngân sách.
    var spent: Int
    /// Chi trong ngân sách của kỳ liền trước (cả kỳ); nil khi kỳ đó chưa chi gì nên không có gì để so.
    var previousSpent: Int?
    var topCategoryKey: String?
    var topCategoryAmount: Int
    /// Ngân sách tháng tương đương, chỉ có khi tổng kết tháng và đã đặt ngân sách.
    var budget: Int?
    var daysWithSpending: Int

    /// Dương là còn dư, âm là vượt. Chỉ có khi có ngân sách.
    var leftover: Int? { budget.map { $0 - spent } }
    /// Dương là chi nhiều hơn kỳ trước.
    var delta: Int? { previousSpent.map { spent - $0 } }
}

enum SummaryComposer {
    /// Số liệu của kỳ chứa `date`. Nil khi kỳ đó chưa chi gì trong ngân sách (không có gì để báo).
    static func make(
        kind: SummaryKind, records: [SpendingRecord], budget: BudgetSetting?, containing date: Date, calendar: Calendar
    ) -> PeriodSummary? {
        let component: Calendar.Component = kind == .week ? .weekOfYear : .month
        guard let interval = calendar.dateInterval(of: component, for: date),
              let before = calendar.date(byAdding: component, value: -1, to: interval.start),
              let previous = calendar.dateInterval(of: component, for: before) else { return nil }

        let inBudget = records.filter { !$0.isOutsideBudget }
        let current = inBudget.filter { interval.contains($0.date) }
        let spent = current.reduce(0) { $0 + $1.amount }
        guard spent > 0 else { return nil }

        let previousSpent = inBudget.filter { previous.contains($0.date) }.reduce(0) { $0 + $1.amount }
        let byCategory = Dictionary(grouping: current, by: \.categoryKey).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let top = byCategory.max { ($0.value, $1.key) < ($1.value, $0.key) }
        let monthlyBudget = kind == .month ? budget?.monthlyEquivalent(now: date, calendar: calendar) : nil
        return PeriodSummary(
            kind: kind,
            interval: interval,
            spent: spent,
            previousSpent: previousSpent > 0 ? previousSpent : nil,
            topCategoryKey: top?.key,
            topCategoryAmount: top?.value ?? 0,
            budget: (monthlyBudget ?? 0) > 0 ? monthlyBudget : nil,
            daysWithSpending: Set(current.map { calendar.startOfDay(for: $0.date) }).count
        )
    }
}

/// Lịch gửi thông báo tổng kết: tối ngày cuối của tuần, và tối ngày cuối của tháng.
enum SummaryPlanner {
    static let weeklyTime = (hour: 20, minute: 0)
    /// Lệch 15 phút để không trùng thông báo tuần khi cuối tháng cũng là cuối tuần.
    static let monthlyTime = (hour: 20, minute: 15)

    /// Lần gửi kế tiếp, chưa qua so với `now`. Nil nếu không tính được ngày.
    static func nextFire(kind: SummaryKind, now: Date, calendar: Calendar) -> Date? {
        let component: Calendar.Component = kind == .week ? .weekOfYear : .month
        let time = kind == .week ? weeklyTime : monthlyTime
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: component, value: offset, to: now),
                  let interval = calendar.dateInterval(of: component, for: day),
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
                  let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: lastDay),
                  fire > now else { continue }
            return fire
        }
        return nil
    }
}
