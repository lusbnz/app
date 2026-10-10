import Foundation

extension AppSettings {
    /// Phần cài đặt đi cùng bản sao lưu: ngân sách và tỷ giá người dùng đã chỉnh.
    func backupSettings(ratesIn defaults: UserDefaults = AppGroup.defaults) -> BackupSettings {
        BackupSettings(
            monthlyBudget: monthlyBudget, weeklyBudget: weeklyBudget, budgetPeriod: budgetPeriod.rawValue,
            exchangeRates: ExchangeRates.load(from: defaults).stored
        )
    }

    /// Áp phần cài đặt đã hợp nhất (`BackupMerger.merge`) khi khôi phục.
    func apply(_ backup: BackupSettings, ratesIn defaults: UserDefaults = AppGroup.defaults) {
        if backup.monthlyBudget != monthlyBudget { monthlyBudget = backup.monthlyBudget }
        if backup.weeklyBudget != weeklyBudget { weeklyBudget = backup.weeklyBudget }
        if let period = BudgetPeriod(rawValue: backup.budgetPeriod), period != budgetPeriod { budgetPeriod = period }
        ExchangeRates(stored: backup.exchangeRates).save(to: defaults)
    }
}
