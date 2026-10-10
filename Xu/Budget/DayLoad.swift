import Foundation

/// Mức một ngày đã dùng so với hạn mức ngày, để vẽ vệt highlight ở tiêu đề ngày.
struct DayLoad: Equatable, Sendable {
    /// Phần vệt được tô, từ 0 đến 1.
    var fraction: Double
    /// Tiêu quá hạn mức ngày.
    var isOver: Bool

    /// Nil khi chưa có hạn mức ngày (chưa đặt ngân sách) nên không có gì để so.
    static func make(spent: Int, allowance: Int) -> DayLoad? {
        guard allowance > 0 else { return nil }
        let ratio = Double(max(spent, 0)) / Double(allowance)
        return DayLoad(fraction: min(ratio, 1), isOver: spent > allowance)
    }

    /// Hạn mức ngày của một ngày đã qua: ngân sách của kỳ chia đều cho số ngày của kỳ chứa ngày đó.
    static func pastDayAllowance(_ setting: BudgetSetting, day: Date, calendar: Calendar) -> Int {
        BudgetCalculator.dailyAverage(budget: setting.amount, period: setting.period, now: day, calendar: calendar)
    }
}
