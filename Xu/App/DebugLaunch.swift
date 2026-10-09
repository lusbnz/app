#if DEBUG
import Foundation
import SwiftData

/// Tham số khởi chạy chỉ có ở bản Debug, để xem nhanh các màn hình trên máy ảo:
/// `-reset` xóa sạch, `-demo` nạp dữ liệu mẫu, `-open entry|month|settings|paywall|receipt`, `-text "phở 45k"`.
/// `-open receipt` đưa sẵn một hóa đơn mẫu vào bộ đọc. `-pro` mở Xu Pro, `-ask "câu hỏi"` hỏi Xu.
@MainActor
enum DebugLaunch {
    static func apply(settings: AppSettings, appState: AppState, container: ModelContainer) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let context = container.mainContext
        if arguments.contains("-reset") {
            try? context.delete(model: Expense.self)
            try? context.delete(model: Loan.self)
            try? context.delete(model: CategoryRule.self)
            settings.monthlyBudget = 0
            settings.suggestionsEnabled = false
            settings.remindsAtNine = false
            settings.leaveReminderEnabled = false
            settings.lastQuestion = ""
            settings.lastAnswer = ""
            AppGroup.defaults.removeObject(forKey: "saveQuota")
        }
        if arguments.contains("-demo") {
            settings.monthlyBudget = 9_000_000
            settings.suggestionsEnabled = true
            let existing = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0
            if existing == 0 { seed(context) }
        }
        if arguments.contains("-pro") {
            EntitlementStore.shared.grantForDebug()
        }
        try? context.save()
        let screen = value(after: "-open")
        let text = value(after: "-text") ?? ""
        let question = value(after: "-ask")
        // Chờ giao diện gốc dựng xong rồi mới điều hướng, như khi người dùng chạm.
        Task {
            try? await Task.sleep(for: .seconds(1))
            switch screen {
            case "entry": appState.openEntry(text: text)
            case "month": appState.showsMonth = true
            case "settings": appState.showsSettings = true
            case "paywall": appState.showsPaywall = true
            case "receipt":
                appState.receiptImage = SampleReceipt.image()
                appState.showsReceipt = true
            default: break
            }
            if let question { appState.ask(question) }
        }
    }

    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let noon = calendar.date(bySettingHour: 12, minute: 15, second: 0, of: now) ?? now
        func add(_ name: String, _ amount: Int, _ category: String, daysAgo: Int, hour: Int = 12) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon),
                  let date = calendar.date(bySettingHour: hour, minute: 15, second: 0, of: day),
                  date <= now || daysAgo > 0 else { return }
            let expense = Expense(name: name, amount: amount, categoryKey: category, date: min(date, now))
            expense.latitude = 10.7769
            expense.longitude = 106.7009
            context.insert(expense)
        }
        add("phở", 45_000, "food", daysAgo: 0, hour: 7)
        add("grab", 32_000, "transport", daysAgo: 0, hour: 8)
        for day in 1...min(7, max(1, calendar.component(.day, from: now) - 1)) {
            add("phở", 45_000, "food", daysAgo: day, hour: 7)
            add("cf", 29_000, "food", daysAgo: day, hour: 9)
            add("cơm tấm", 55_000, "food", daysAgo: day, hour: 12)
            add(day.isMultiple(of: 2) ? "đổ xăng" : "grab", day.isMultiple(of: 2) ? 80_000 : 32_000, "transport", daysAgo: day, hour: 18)
            add("bún chả", 60_000, "food", daysAgo: day, hour: 19)
        }
        context.insert(Loan(person: "Minh", amount: 200_000))
    }
}
#endif
