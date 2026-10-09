import Foundation
import SwiftData

/// Hạn mức tháng của một danh mục, chỉ để cảnh báo. `categoryKey` trỏ tới danh mục có sẵn hoặc `CustomCategory.key`.
@Model final class CategoryBudget {
    var categoryKey: String = ""
    var amount: Int = 0
    var updatedAt: Date = Date()

    init(categoryKey: String, amount: Int) {
        self.categoryKey = categoryKey
        self.amount = amount
    }
}

extension [CategoryBudget] {
    /// Bảng tra danh mục sang hạn mức. Khi trùng khóa (đồng bộ iCloud có thể tạo bản lặp), bản mới hơn thắng.
    var lookup: [String: Int] {
        var table: [String: Int] = [:]
        for budget in sorted(by: { $0.updatedAt < $1.updatedAt }) where budget.amount > 0 {
            table[budget.categoryKey] = budget.amount
        }
        return table
    }
}
