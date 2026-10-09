import SwiftData
import WidgetKit

struct XuEntry: TimelineEntry {
    var date: Date
    var hasBudget: Bool
    var remaining: Int
    var fraction: Double
    /// Các khoản hay ghi nhất, dùng cho nút một chạm.
    var quick: [Suggestion]
    var isPro: Bool
    var canSave: Bool

    static let sample = XuEntry(
        date: Date(), hasBudget: true, remaining: 194_000, fraction: 0.65,
        quick: [
            Suggestion(name: "cf", amount: 29_000, categoryKey: "food"),
            Suggestion(name: "phở", amount: 45_000, categoryKey: "food"),
        ],
        isPro: true, canSave: true
    )
}

/// Đọc dữ liệu chung qua App Group.
enum WidgetData {
    static func entry(at date: Date, calendar: Calendar = .current) -> XuEntry {
        let budget = AppGroup.defaults.integer(forKey: SettingsKey.monthlyBudget)
        let context = ModelContext(XuStore.shared)
        let since = calendar.date(byAdding: .day, value: -35, to: date) ?? date
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since }))) ?? []
        let status = BudgetCalculator.status(
            monthlyBudget: budget, entries: expenses.map(\.budgetEntry), now: date, calendar: calendar
        )
        let quick = expenses.map(\.suggestionRecord).ranked().prefix(2).map(\.suggestion)
        return XuEntry(
            date: date, hasBudget: budget > 0, remaining: status.remainingToday, fraction: status.todayFraction,
            quick: Array(quick), isPro: SaveGate.isPro, canSave: SaveGate.canSave(now: date, calendar: calendar)
        )
    }
}

struct XuTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> XuEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (XuEntry) -> Void) {
        completion(context.isPreview ? .sample : WidgetData.entry(at: Date()))
    }

    /// Một mục cho bây giờ và một mục lúc 0:00, khi hạn mức ngày mới bắt đầu.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<XuEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        var entries = [WidgetData.entry(at: now)]
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        entries.append(WidgetData.entry(at: midnight))
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}
