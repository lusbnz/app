import Foundation
import SwiftData

/// Khoản định kỳ và hạn mức danh mục.
extension ExpenseRecorder {
    // MARK: - Khoản định kỳ

    @discardableResult
    func addRecurring(
        name: String, amount: Int, categoryKey: String, dayOfMonth: Int, isOutsideBudget: Bool, now: Date,
        frequency: RecurringFrequency = .monthly, weekday: Int = 2, monthOfYear: Int = 1, autoRecord: Bool = false
    ) -> RecurringExpense {
        let item = RecurringExpense(
            name: name, amount: amount, categoryKey: categoryKey, dayOfMonth: dayOfMonth,
            isOutsideBudget: isOutsideBudget, createdAt: now,
            frequency: frequency, weekday: weekday, monthOfYear: monthOfYear, autoRecord: autoRecord
        )
        context.insert(item)
        commit()
        return item
    }

    func updateRecurring(
        _ item: RecurringExpense, name: String, amount: Int, categoryKey: String, dayOfMonth: Int, isOutsideBudget: Bool,
        frequency: RecurringFrequency = .monthly, weekday: Int = 2, monthOfYear: Int = 1, autoRecord: Bool = false
    ) {
        // Đổi lịch thì kỳ đã xử lý không còn đúng nghĩa, nên bắt đầu lại.
        if item.frequency != frequency { item.handledMonth = "" }
        item.frequency = frequency
        item.weekday = weekday
        item.monthOfYear = monthOfYear
        item.autoRecord = autoRecord
        item.name = name
        item.amount = amount
        item.categoryKey = categoryKey
        item.dayOfMonth = dayOfMonth
        item.isOutsideBudget = isOutsideBudget
        commit()
    }

    func deleteRecurring(_ item: RecurringExpense) {
        context.delete(item)
        commit()
    }

    func recurring(id: UUID) -> RecurringExpense? {
        try? context.fetch(FetchDescriptor<RecurringExpense>(predicate: #Predicate { $0.id == id })).first
    }

    /// Ghi khoản định kỳ đến hạn và đánh dấu tháng này đã xong. Nơi gọi phải kiểm tra `SaveGate.canSave` trước.
    /// Trả về nil khi khoản không còn đến hạn (đã ghi hay bỏ qua ở nơi khác).
    @discardableResult
    func recordRecurring(_ item: RecurringExpense, now: Date, calendar: Calendar) -> SavedBatch? {
        guard RecurringPlanner.isDue(item.item, now: now, calendar: calendar) else { return nil }
        let date = RecurringPlanner.expenseDate(for: item.item, now: now, calendar: calendar)
        item.handledMonth = RecurringPlanner.periodKey(now, frequency: item.frequency, calendar: calendar)
        let draft = ExpenseDraft(
            name: item.name, amount: item.amount, categoryKey: item.categoryKey, isOutsideBudget: item.isOutsideBudget
        )
        return record([.expense(draft)], in: RecordContext(rawText: item.name, date: date))
    }

    func skipRecurring(_ item: RecurringExpense, now: Date, calendar: Calendar) {
        item.handledMonth = RecurringPlanner.periodKey(now, frequency: item.frequency, calendar: calendar)
        commit()
    }

    /// Tự ghi các khoản đặt "tự ghi" đã đến hạn, theo thứ tự tạo. Dừng khi hết lượt ghi miễn phí trong ngày
    /// (khoản còn lại hiện ở màn Hôm nay như khoản thường). Trả về các lần ghi đã làm.
    @discardableResult
    func recordAutomaticRecurring(now: Date, calendar: Calendar) -> [SavedBatch] {
        let items = ((try? context.fetch(FetchDescriptor<RecurringExpense>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter { $0.autoRecord && RecurringPlanner.isDue($0.item, now: now, calendar: calendar) }
        var batches: [SavedBatch] = []
        for item in items {
            guard SaveGate.canSave(now: now, calendar: calendar),
                  let batch = recordRecurring(item, now: now, calendar: calendar) else { break }
            batches.append(batch)
        }
        return batches
    }

    // MARK: - Hạn mức danh mục

    func limits() -> [String: Int] {
        ((try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []).lookup
    }

    /// Đặt hạn mức tháng cho một danh mục; `amount` nil hoặc 0 thì bỏ hạn mức.
    func setLimit(categoryKey: String, amount: Int?) {
        let existing = (try? context.fetch(FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.categoryKey == categoryKey }))) ?? []
        if let amount, amount > 0 {
            if let first = existing.first {
                first.amount = amount
                first.updatedAt = Date()
                existing.dropFirst().forEach(context.delete)
            } else {
                context.insert(CategoryBudget(categoryKey: categoryKey, amount: amount))
            }
        } else {
            existing.forEach(context.delete)
        }
        commit()
    }

    /// Cảnh báo cho danh mục mà lần ghi vừa rồi làm gần chạm hoặc vượt hạn mức. Gọi sau khi đã lưu.
    /// Chỉ tính khoản nằm trong tháng của `now` và trong ngân sách.
    func limitWarning(for items: [RecordItem], defaultDate: Date, now: Date, calendar: Calendar) -> String? {
        let limits = limits()
        guard !limits.isEmpty, let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        var added: [String: Int] = [:]
        for case .expense(let draft) in items where !draft.isOutsideBudget && month.contains(draft.date ?? defaultDate) {
            added[draft.categoryKey, default: 0] += draft.amount
        }
        let spent = Dictionary(grouping: expenses(since: month.start).filter { !$0.isOutsideBudget && month.contains($0.date) }, by: \.categoryKey)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        var worst: (level: LimitLevel, message: String)?
        for (key, amount) in added.sorted(by: { $0.key < $1.key }) {
            guard let limit = limits[key] else { continue }
            let total = spent[key] ?? 0
            guard let level = CategoryBudgetCalculator.crossing(limit: limit, spentBefore: total - amount, added: amount),
                  worst.map({ level > $0.level }) ?? true else { continue }
            let title = categoryTitle(for: key)
            let message = level == .over
                ? String(localized: "\(title) vượt hạn mức \(MoneyFormatter.short(total - limit))")
                : String(localized: "\(title) đã dùng \(total * 100 / limit)% hạn mức")
            worst = (level, message)
        }
        return worst?.message
    }

    /// Tên danh mục để nói trong cảnh báo (không dùng `CategoryCatalog` vì nó thuộc tầng giao diện).
    func categoryTitle(for key: String) -> String {
        if CategoryNaming.isCustom(key) {
            let found = (try? context.fetch(FetchDescriptor<CustomCategory>(predicate: #Predicate { $0.key == key })))?.first
            return found?.name ?? String(localized: SpendingCategory.other.title)
        }
        return String(localized: SpendingCategory(key: key).title)
    }
}
