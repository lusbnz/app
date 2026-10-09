import AppIntents

/// Mở thẳng ô gõ. Hợp với Nút Tác vụ.
struct OpenEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Mở ô gõ"
    static let description = IntentDescription("Mở Xu ngay ở ô gõ để ghi khoản chi.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.openEntry()
        return .result()
    }
}

struct XuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Ghi chi tiêu trong \(.applicationName)",
                "Ghi vào \(.applicationName)",
                "\(.applicationName) ghi chi tiêu",
            ],
            shortTitle: "Ghi chi tiêu",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenEntryIntent(),
            phrases: [
                "Mở ô gõ \(.applicationName)",
                "Mở \(.applicationName) để ghi",
            ],
            shortTitle: "Mở ô gõ",
            systemImageName: "keyboard"
        )
    }
}
