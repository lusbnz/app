import Foundation
import SwiftData

/// Khoản chi lặp lại mỗi tháng. Đến hạn thì Xu nhắc và hỏi, không tự ghi.
@Model final class RecurringExpense {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Int = 0
    var categoryKey: String = "other"
    var dayOfMonth: Int = 1
    var isOutsideBudget: Bool = false
    var createdAt: Date = Date()
    /// "2026-10": tháng gần nhất đã ghi hoặc bỏ qua.
    var handledMonth: String = ""

    init(name: String, amount: Int, categoryKey: String, dayOfMonth: Int, isOutsideBudget: Bool = false, createdAt: Date = Date()) {
        self.name = name
        self.amount = amount
        self.categoryKey = categoryKey
        self.dayOfMonth = dayOfMonth
        self.isOutsideBudget = isOutsideBudget
        self.createdAt = createdAt
    }

    var item: RecurringItem {
        RecurringItem(
            id: id, name: name, amount: amount, categoryKey: categoryKey, dayOfMonth: dayOfMonth,
            isOutsideBudget: isOutsideBudget, createdAt: createdAt, handledMonth: handledMonth
        )
    }
}
