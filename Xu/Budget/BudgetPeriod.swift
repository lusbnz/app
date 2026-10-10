import Foundation

/// Ngân sách tính theo tháng hay theo tuần.
enum BudgetPeriod: String, CaseIterable, Identifiable, Sendable {
    case month, week

    var id: String { rawValue }

    /// Kỳ chứa `date`: cả tháng hoặc cả tuần.
    func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: self == .month ? .month : .weekOfYear, for: date)
    }

    /// Số ngày của kỳ chứa `date`.
    func dayCount(containing date: Date, calendar: Calendar) -> Int {
        switch self {
        case .month: calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        case .week: calendar.range(of: .day, in: .weekOfYear, for: date)?.count ?? 7
        }
    }
}

/// Ngân sách đang dùng: một số tiền cho một kỳ.
struct BudgetSetting: Equatable, Sendable {
    var period: BudgetPeriod
    /// Ngân sách của một kỳ (một tháng hoặc một tuần), đơn vị đồng.
    var amount: Int

    static func monthly(_ amount: Int) -> BudgetSetting {
        BudgetSetting(period: .month, amount: amount)
    }

    /// Ngân sách tuần gợi ý khi đổi từ tháng sang tuần: bảy phần ba mươi của ngân sách tháng, làm tròn xuống nghìn.
    static func suggestedWeekly(fromMonthly monthly: Int) -> Int {
        BudgetCalculator.floorToThousand(monthly * 7 / 30)
    }

    /// Ngân sách tháng tương đương, cho những chỗ chỉ hiểu tháng (Hỏi Pennyline, tổng kết cuối tháng).
    func monthlyEquivalent(now: Date, calendar: Calendar) -> Int {
        switch period {
        case .month: amount
        case .week: amount * BudgetPeriod.month.dayCount(containing: now, calendar: calendar) / 7
        }
    }
}
