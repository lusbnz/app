import Foundation

/// Mức dùng hạn mức của một danh mục. Luôn dùng để cảnh báo; hạn mức ngày chỉ đổi khi người dùng bật
/// "Hạn mức danh mục tính vào hạn mức ngày" (xem `BudgetCalculator.status(...categoryLimits...)`).
enum LimitLevel: Int, Comparable, Sendable {
    case ok, near, over

    static func < (lhs: LimitLevel, rhs: LimitLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct CategoryLimitStatus: Equatable, Sendable, Identifiable {
    var key: String
    var limit: Int
    var spent: Int

    var id: String { key }
    var remaining: Int { limit - spent }
    var level: LimitLevel { CategoryBudgetCalculator.level(spent: spent, limit: limit) }
    /// Tỉ lệ đã dùng, từ 0 đến 1.
    var fraction: Double { limit > 0 ? min(1, max(0, Double(spent) / Double(limit))) : 0 }
}

enum CategoryBudgetCalculator {
    /// Từ 80% hạn mức là "gần chạm".
    static let nearPercent = 80

    /// Chạm đúng hạn mức vẫn là "gần chạm"; chỉ vượt hẳn mới là "vượt".
    static func level(spent: Int, limit: Int) -> LimitLevel {
        guard limit > 0 else { return .ok }
        if spent > limit { return .over }
        return spent * 100 >= limit * nearPercent ? .near : .ok
    }

    /// Hạn mức từng danh mục trong tháng của `now`, nhiều phần trăm đã dùng nhất trước.
    /// Khoản ngoài ngân sách không tính.
    static func statuses(limits: [String: Int], records: [SpendingRecord], now: Date, calendar: Calendar) -> [CategoryLimitStatus] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        var spent: [String: Int] = [:]
        for record in records where !record.isOutsideBudget && month.contains(record.date) {
            spent[record.categoryKey, default: 0] += record.amount
        }
        return limits
            .filter { $0.value > 0 }
            .map { CategoryLimitStatus(key: $0.key, limit: $0.value, spent: spent[$0.key] ?? 0) }
            .sorted { (ratio($1), $0.key) < (ratio($0), $1.key) }
    }

    private static func ratio(_ status: CategoryLimitStatus) -> Double {
        Double(status.spent) / Double(status.limit)
    }

    /// Mức mới khi một lần ghi làm danh mục xấu đi (ok sang gần chạm, hoặc sang vượt); nil nếu không đổi hay vẫn ổn.
    static func crossing(limit: Int, spentBefore: Int, added: Int) -> LimitLevel? {
        let after = level(spent: spentBefore + added, limit: limit)
        return after > level(spent: spentBefore, limit: limit) ? after : nil
    }
}
