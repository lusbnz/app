import Foundation
import Testing
@testable import Xu

@MainActor
struct AppPreferencesTests {
    private func suite() -> UserDefaults {
        let name = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
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
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
        #expect(settings.needsRelaunchForLanguage)
        settings.language = .system
        // Xóa ghi đè thì đọc lại sẽ rơi về ngôn ngữ hệ thống, không còn là "en".
        #expect(defaults.stringArray(forKey: "AppleLanguages") != ["en"])
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
