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

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        monthlyBudget = defaults.integer(forKey: SettingsKey.monthlyBudget)
        remindsAtNine = defaults.bool(forKey: SettingsKey.remindsAtNine)
        suggestionsEnabled = defaults.bool(forKey: SettingsKey.suggestionsEnabled)
        leaveReminderEnabled = defaults.bool(forKey: SettingsKey.leaveReminderEnabled)
        lastQuestion = defaults.string(forKey: SettingsKey.lastQuestion) ?? ""
        lastAnswer = defaults.string(forKey: SettingsKey.lastAnswer) ?? ""
    }
}
