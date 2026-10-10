import Foundation
import Testing
@testable import Xu

@MainActor
struct AppPreferencesTests {
    private let suiteName = "AppPreferencesTests-\(UUID().uuidString)"

    private func suite() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Giá trị thật đã lưu trong suite; `stringArray(forKey:)` còn đọc cả tham số dòng lệnh (`-testLanguage`).
    private func storedLanguages(_ defaults: UserDefaults) -> [String]? {
        defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String]
    }

    @Test func appearanceDefaultsToSystemAndPersists() {
        let defaults = suite()
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        #expect(settings.appearance == .system)
        #expect(settings.appearance.colorScheme == nil)
        settings.appearance = .dark
        #expect(AppSettings(defaults: defaults, standardDefaults: defaults).appearance == .dark)
        #expect(AppAppearance.light.colorScheme == .light)
    }

    @Test func languageWritesAppleLanguagesAndNeedsRelaunch() {
        let defaults = suite()
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        #expect(settings.language == .system)
        #expect(!settings.needsRelaunchForLanguage)
        settings.language = .english
        #expect(storedLanguages(defaults) == ["en"])
        #expect(settings.needsRelaunchForLanguage)
        settings.language = .system
        #expect(storedLanguages(defaults) == nil)
        #expect(!settings.needsRelaunchForLanguage)
    }

    @Test func languageIsRestoredOnNextLaunch() {
        let defaults = suite()
        AppSettings(defaults: defaults, standardDefaults: defaults).language = .vietnamese
        let next = AppSettings(defaults: defaults, standardDefaults: defaults)
        #expect(next.language == .vietnamese)
        #expect(next.launchLanguage == .vietnamese)
        #expect(!next.needsRelaunchForLanguage)
    }
}
