import Foundation

extension BudgetSetting {
    /// Ngân sách đang dùng, đọc từ App Group để intent và thông báo (không có `AppSettings`) dùng chung với app.
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> BudgetSetting {
        let monthly = defaults.integer(forKey: SettingsKey.monthlyBudget)
        let period = BudgetPeriod(rawValue: defaults.string(forKey: SettingsKey.budgetPeriod) ?? "") ?? .month
        guard period == .week else { return .monthly(monthly) }
        let weekly = defaults.integer(forKey: SettingsKey.weeklyBudget)
        return BudgetSetting(period: .week, amount: weekly > 0 ? weekly : suggestedWeekly(fromMonthly: monthly))
    }
}
