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

    /// Hạn mức ngày của một ngày đã qua: ngân sách chia đều cho số ngày của tháng đó.
    static func pastDayAllowance(monthlyBudget: Int, day: Date, calendar: Calendar) -> Int {
        BudgetCalculator.dailyAverage(monthlyBudget: monthlyBudget, now: day, calendar: calendar)
    }
}
