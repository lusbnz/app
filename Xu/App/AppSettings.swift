import Foundation
import Observation

/// Cài đặt của người dùng, lưu trong UserDefaults của App Group.
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    /// 0 nghĩa là chưa qua màn hình lần đầu mở app.
    var monthlyBudget: Int { didSet { defaults.set(monthlyBudget, forKey: SettingsKey.monthlyBudget) } }
    var remindsAtNine: Bool { didSet { defaults.set(remindsAtNine, forKey: SettingsKey.remindsAtNine) } }
    var suggestionsEnabled: Bool { didSet { defaults.set(suggestionsEnabled, forKey: SettingsKey.suggestionsEnabled) } }
    var leaveReminderEnabled: Bool { didSet { defaults.set(leaveReminderEnabled, forKey: SettingsKey.leaveReminderEnabled) } }
    var lastQuestion: String { didSet { defaults.set(lastQuestion, forKey: SettingsKey.lastQuestion) } }
    var lastAnswer: String { didSet { defaults.set(lastAnswer, forKey: SettingsKey.lastAnswer) } }

    /// Hạn mức danh mục giữ riêng phần tiền của nó, hạn mức ngày chỉ tính trên phần còn lại.
    var limitsShapeDaily: Bool { didSet { defaults.set(limitsShapeDaily, forKey: SettingsKey.limitsShapeDaily) } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: SettingsKey.appearance) } }
    var language: AppLanguage { didSet { AppLanguage.apply(language, to: standardDefaults) } }
    /// Ngôn ngữ lúc app khởi động; khác `language` nghĩa là cần mở lại app.
    @ObservationIgnored let launchLanguage: AppLanguage
    @ObservationIgnored private let standardDefaults: UserDefaults

    /// Hạn mức danh mục dùng để tính hạn mức ngày; rỗng khi người dùng chưa bật.
    func dailyLimits(_ budgets: [CategoryBudget]) -> [String: Int] {
        limitsShapeDaily ? budgets.lookup : [:]
    }

    var needsRelaunchForLanguage: Bool { language != launchLanguage }

    init(defaults: UserDefaults = AppGroup.defaults, standardDefaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.standardDefaults = standardDefaults
        limitsShapeDaily = defaults.bool(forKey: SettingsKey.limitsShapeDaily)
        appearance = AppAppearance(rawValue: defaults.string(forKey: SettingsKey.appearance) ?? "") ?? .system
        let language = AppLanguage(rawValue: standardDefaults.string(forKey: SettingsKey.appLanguage) ?? "") ?? .system
        self.language = language
        launchLanguage = language
        monthlyBudget = defaults.integer(forKey: SettingsKey.monthlyBudget)
        remindsAtNine = defaults.bool(forKey: SettingsKey.remindsAtNine)
        suggestionsEnabled = defaults.bool(forKey: SettingsKey.suggestionsEnabled)
        leaveReminderEnabled = defaults.bool(forKey: SettingsKey.leaveReminderEnabled)
        lastQuestion = defaults.string(forKey: SettingsKey.lastQuestion) ?? ""
        lastAnswer = defaults.string(forKey: SettingsKey.lastAnswer) ?? ""
    }
}
