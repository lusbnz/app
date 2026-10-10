import Foundation
import Observation

/// Cài đặt của người dùng, lưu trong UserDefaults của App Group.
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// 0 nghĩa là chưa qua màn hình lần đầu mở app.
    var monthlyBudget: Int { didSet { defaults.set(monthlyBudget, forKey: SettingsKey.monthlyBudget) } }
    /// Ngân sách tính theo tháng hay theo tuần. Ngân sách tháng vẫn được giữ khi chuyển sang tuần.
    var budgetPeriod: BudgetPeriod { didSet { defaults.set(budgetPeriod.rawValue, forKey: SettingsKey.budgetPeriod) } }
    /// 0 là chưa đặt; khi chuyển sang tính theo tuần thì lấy gợi ý từ ngân sách tháng.
    var weeklyBudget: Int { didSet { defaults.set(weeklyBudget, forKey: SettingsKey.weeklyBudget) } }
    /// Thông báo tổng kết cuối tuần và cuối tháng. Mặc định tắt.
    var weeklySummary: Bool { didSet { defaults.set(weeklySummary, forKey: SettingsKey.weeklySummary) } }
    var monthlySummary: Bool { didSet { defaults.set(monthlySummary, forKey: SettingsKey.monthlySummary) } }
    var remindsAtNine: Bool { didSet { defaults.set(remindsAtNine, forKey: SettingsKey.remindsAtNine) } }
    var suggestionsEnabled: Bool { didSet { defaults.set(suggestionsEnabled, forKey: SettingsKey.suggestionsEnabled) } }
    var leaveReminderEnabled: Bool { didSet { defaults.set(leaveReminderEnabled, forKey: SettingsKey.leaveReminderEnabled) } }
    var lastQuestion: String { didSet { defaults.set(lastQuestion, forKey: SettingsKey.lastQuestion) } }
    var lastAnswer: String { didSet { defaults.set(lastAnswer, forKey: SettingsKey.lastAnswer) } }

    /// Hạn mức danh mục giữ riêng phần tiền của nó, hạn mức ngày chỉ tính trên phần còn lại.
    var limitsShapeDaily: Bool { didSet { defaults.set(limitsShapeDaily, forKey: SettingsKey.limitsShapeDaily) } }
    /// Tự tra tên quán ở chỗ ghi bằng dịch vụ của Apple (gửi vị trí cho Apple). Mặc định tắt.
    var placeLookupEnabled: Bool { didSet { defaults.set(placeLookupEnabled, forKey: SettingsKey.placeLookup) } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: SettingsKey.appearance) } }
    var language: AppLanguage { didSet { AppLanguage.apply(language, to: standardDefaults) } }
    /// Ngôn ngữ lúc app khởi động; khác `language` nghĩa là cần mở lại app.
    @ObservationIgnored let launchLanguage: AppLanguage
    @ObservationIgnored private let standardDefaults: UserDefaults

    /// Ngân sách của kỳ đang dùng (tháng hoặc tuần).
    var budgetSetting: BudgetSetting {
        BudgetSetting(period: budgetPeriod, amount: budgetPeriod == .week ? weeklyBudget : monthlyBudget)
    }

    /// Đổi kỳ ngân sách. Lần đầu chuyển sang tuần thì gợi ý số tiền từ ngân sách tháng.
    func setBudgetPeriod(_ period: BudgetPeriod) {
        if period == .week, weeklyBudget <= 0 {
            weeklyBudget = BudgetSetting.suggestedWeekly(fromMonthly: monthlyBudget)
        }
        budgetPeriod = period
    }

    /// Đặt ngân sách cho kỳ đang dùng.
    func setActiveBudget(_ amount: Int) {
        if budgetPeriod == .week { weeklyBudget = amount } else { monthlyBudget = amount }
    }

    /// Hạn mức danh mục dùng để tính hạn mức ngày; rỗng khi người dùng chưa bật.
    func dailyLimits(_ budgets: [CategoryBudget]) -> [String: Int] {
        limitsShapeDaily && budgetPeriod == .month ? budgets.lookup : [:]
    }

    var needsRelaunchForLanguage: Bool { language != launchLanguage }

    init(defaults: UserDefaults = AppGroup.defaults, standardDefaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.standardDefaults = standardDefaults
        placeLookupEnabled = defaults.bool(forKey: SettingsKey.placeLookup)
        limitsShapeDaily = defaults.bool(forKey: SettingsKey.limitsShapeDaily)
        appearance = AppAppearance(rawValue: defaults.string(forKey: SettingsKey.appearance) ?? "") ?? .system
        let language = AppLanguage(rawValue: standardDefaults.string(forKey: SettingsKey.appLanguage) ?? "") ?? .system
        self.language = language
        launchLanguage = language
        monthlyBudget = defaults.integer(forKey: SettingsKey.monthlyBudget)
        weeklyBudget = defaults.integer(forKey: SettingsKey.weeklyBudget)
        budgetPeriod = BudgetPeriod(rawValue: defaults.string(forKey: SettingsKey.budgetPeriod) ?? "") ?? .month
        weeklySummary = defaults.bool(forKey: SettingsKey.weeklySummary)
        monthlySummary = defaults.bool(forKey: SettingsKey.monthlySummary)
        remindsAtNine = defaults.bool(forKey: SettingsKey.remindsAtNine)
        suggestionsEnabled = defaults.bool(forKey: SettingsKey.suggestionsEnabled)
        leaveReminderEnabled = defaults.bool(forKey: SettingsKey.leaveReminderEnabled)
        lastQuestion = defaults.string(forKey: SettingsKey.lastQuestion) ?? ""
        lastAnswer = defaults.string(forKey: SettingsKey.lastAnswer) ?? ""
    }
}
