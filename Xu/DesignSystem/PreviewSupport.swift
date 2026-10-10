import SwiftData
import SwiftUI

/// Dữ liệu mẫu trong bộ nhớ cho #Preview.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = XuStore.inMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        func add(_ name: String, _ amount: Int, _ category: String, daysAgo: Int = 0, outside: Bool = false) -> Expense {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let expense = Expense(name: name, amount: amount, categoryKey: category, date: date)
            expense.isOutsideBudget = outside
            context.insert(expense)
            return expense
        }
        _ = add("phở", 45_000, "food")
        _ = add("grab", 32_000, "transport")
        _ = add("cf", 29_000, "food")
        let shared = add("nhậu", 115_000, "food")
        shared.originalAmount = 460_000
        shared.splitCount = 4
        _ = add("tai nghe", 1_200_000, "shopping", outside: true)
        _ = add("cơm tấm", 55_000, "food", daysAgo: 1)
        _ = add("đổ xăng", 80_000, "transport", daysAgo: 1)
        _ = add("áo", 350_000, "shopping", daysAgo: 2)
        context.insert(Loan(person: "Minh", amount: 200_000))
        return container
    }()

    static var expense: Expense {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Expense>())) ?? []
        return all.first { $0.splitCount != nil } ?? Expense(name: "phở", amount: 45_000, categoryKey: "food")
    }

    static func settings(budget: Int) -> AppSettings {
        let defaults = UserDefaults(suiteName: "preview") ?? .standard
        defaults.removePersistentDomain(forName: "preview")
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        settings.monthlyBudget = budget
        return settings
    }
}

extension View {
    /// Gắn đủ môi trường mà các màn hình cần, với dữ liệu mẫu.
    @MainActor
    func xuPreview(budget: Int = 9_000_000) -> some View {
        modelContainer(PreviewData.container)
            .environment(PreviewData.settings(budget: budget))
            .environment(AppState())
            .environment(AppLock(defaults: UserDefaults(suiteName: "preview") ?? .standard))
            .environment(LocationProvider.shared)
            .environment(EntitlementStore.shared)
            .fontDesign(.rounded)
            .tint(Color.xuToggle)
    }
}
