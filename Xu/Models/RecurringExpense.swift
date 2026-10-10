import Foundation
import SwiftData

/// Khoản chi lặp lại mỗi tuần, hai tuần, tháng, quý hoặc năm. Đến hạn thì Pennyline nhắc và hỏi; chỉ tự ghi khi `autoRecord` bật.
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
    /// `RecurringFrequency.rawValue`; lưu bằng chữ để tương thích CloudKit và đọc được dữ liệu cũ (rỗng là hàng tháng).
    var frequencyRaw: String = "monthly"
    var weekday: Int = 2
    var monthOfYear: Int = 1
    var autoRecord: Bool = false
    var remindDayBefore: Bool = false

    init(
        name: String, amount: Int, categoryKey: String, dayOfMonth: Int, isOutsideBudget: Bool = false, createdAt: Date = Date(),
        frequency: RecurringFrequency = .monthly, weekday: Int = 2, monthOfYear: Int = 1, autoRecord: Bool = false,
        remindDayBefore: Bool = false
    ) {
        self.remindDayBefore = remindDayBefore
        frequencyRaw = frequency.rawValue
        self.weekday = weekday
        self.monthOfYear = monthOfYear
        self.autoRecord = autoRecord
        self.name = name
        self.amount = amount
        self.categoryKey = categoryKey
        self.dayOfMonth = dayOfMonth
        self.isOutsideBudget = isOutsideBudget
        self.createdAt = createdAt
    }

    var frequency: RecurringFrequency {
        get { RecurringFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var item: RecurringItem {
        RecurringItem(
            id: id, name: name, amount: amount, categoryKey: categoryKey, dayOfMonth: dayOfMonth,
            isOutsideBudget: isOutsideBudget, createdAt: createdAt, handledMonth: handledMonth,
            frequency: frequency, weekday: weekday, monthOfYear: monthOfYear, autoRecord: autoRecord,
            remindDayBefore: remindDayBefore
        )
    }
}
