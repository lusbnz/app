import Foundation

extension SpendingSnapshot {
    /// Bảng số liệu tháng của `now` từ các khoản chi trong kho, kèm tên danh mục người dùng đang thấy.
    /// Màn Tháng và ô gõ (Hỏi Pennyline) dùng chung.
    static func make(
        expenses: [Expense], budget: BudgetSetting, customCategories: [CustomCategory], now: Date, calendar: Calendar
    ) -> SpendingSnapshot {
        var snapshot = make(
            records: expenses.map(\.record), monthlyBudget: budget.monthlyEquivalent(now: now, calendar: calendar),
            now: now, calendar: calendar
        )
        snapshot.categoryNames = CategoryCatalog(custom: customCategories).titles
        return snapshot
    }
}
