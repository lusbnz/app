import SwiftUI

/// Giao diện sáng, tối, hoặc theo hệ thống.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    /// nil nghĩa là theo hệ thống.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Theo hệ thống"
        case .light: "Sáng"
        case .dark: "Tối"
        }
    }
}

/// Ngôn ngữ giao diện. Đổi xong phải mở lại app, vì chuỗi `String(localized:)`, thông báo và Siri
/// đều đọc ngôn ngữ lúc khởi động.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, vietnamese = "vi", english = "en"

    var id: String { rawValue }

    /// Tên mỗi ngôn ngữ luôn viết bằng chính ngôn ngữ đó để người dùng tìm được dù đang ở ngôn ngữ nào.
    var title: LocalizedStringKey {
        switch self {
        case .system: "Theo hệ thống"
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }

    /// Giá trị ghi vào `AppleLanguages`; nil nghĩa là bỏ ghi đè để theo hệ thống.
    var appleLanguages: [String]? {
        self == .system ? nil : [rawValue]
    }

    static func apply(_ language: AppLanguage, to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: SettingsKey.appLanguage)
        if let languages = language.appleLanguages {
            defaults.set(languages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}
