import Foundation

enum AppGroup {
    static let identifier = "group.com.quocviet.Xu"

    /// UserDefaults dùng chung với intent. Lùi về mặc định của app khi chưa bật App Group.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// Thư mục dùng chung; nil khi chưa bật App Group.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum SettingsKey {
    static let monthlyBudget = "monthlyBudget"
    static let remindsAtNine = "remindsAtNine"
    static let suggestionsEnabled = "suggestionsEnabled"
    static let leaveReminderEnabled = "leaveReminderEnabled"
    static let lastQuestion = "lastQuestion"
    static let lastAnswer = "lastAnswer"
    static let appearance = "appearance"
    static let lockEnabled = "lockEnabled"
    static let placeLookup = "placeLookup"
    static let limitsShapeDaily = "limitsShapeDaily"
    /// Nằm trong `UserDefaults.standard` (không phải App Group) vì hệ thống đọc `AppleLanguages` ở đó.
    static let appLanguage = "appLanguage"
}
