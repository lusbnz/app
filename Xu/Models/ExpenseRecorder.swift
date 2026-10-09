import Foundation
import SwiftData
import WidgetKit

struct ExpenseDraft: Equatable, Sendable {
    var name: String
    var amount: Int
    var categoryKey: String
    var originalAmount: Int?
    var splitCount: Int?
    var isOutsideBudget: Bool = false
    /// Người dùng đã sửa danh mục, cần lưu thành luật.
    var teachesCategory: Bool = false
}

enum RecordItem: Equatable, Sendable {
    case expense(ExpenseDraft)
    case loan(person: String, amount: Int)
}

/// Ngữ cảnh chung cho một lần lưu.
struct RecordContext: Sendable {
    var rawText: String = ""
    var date: Date = Date()
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var photo: Data?
}

/// Kết quả một lần lưu, đủ để Hoàn tác.
struct SavedBatch: Equatable, Sendable {
    var batchID: UUID
    var loanIDs: [UUID]
    var summary: String
}

/// Nơi duy nhất ghi khoản chi, dùng chung cho ô gõ, gợi ý, intent và thông báo.
@MainActor
struct ExpenseRecorder {
    let context: ModelContext

    @discardableResult
    func record(_ items: [RecordItem], in info: RecordContext = RecordContext()) -> SavedBatch {
        let batchID = UUID()
        var loanIDs: [UUID] = []
        for item in items {
            switch item {
            case .expense(let draft):
                let expense = Expense(name: draft.name, amount: draft.amount, categoryKey: draft.categoryKey, date: info.date)
                expense.createdAt = Date()
                expense.rawText = info.rawText
                expense.batchID = batchID
                expense.isOutsideBudget = draft.isOutsideBudget
                expense.originalAmount = draft.originalAmount
                expense.splitCount = draft.splitCount
                expense.latitude = info.latitude
                expense.longitude = info.longitude
                expense.placeName = info.placeName
                expense.photo = info.photo
                context.insert(expense)
                if draft.teachesCategory { teach(name: draft.name, categoryKey: draft.categoryKey) }
            case .loan(let person, let amount):
                let loan = Loan(person: person, amount: amount, date: info.date)
                loanIDs.append(loan.id)
                context.insert(loan)
            }
        }
        commit()
        return SavedBatch(batchID: batchID, loanIDs: loanIDs, summary: Self.summary(of: items))
    }

    /// Tách một dòng chữ rồi lưu. Trả về nil khi không có khoản nào đủ số tiền.
    func record(text: String, monthlyBudget: Int, now: Date, calendar: Calendar) -> SavedBatch? {
        let allowance = status(monthlyBudget: monthlyBudget, now: now, calendar: calendar).allowanceToday
        let items = ExpenseParser().parse(text, rules: rules(), dailyAllowance: allowance).compactMap { line -> RecordItem? in
            switch line {
            case .expense(let parsed):
                guard let amount = parsed.amount else { return nil }
                return .expense(ExpenseDraft(
                    name: parsed.name, amount: amount, categoryKey: parsed.categoryKey,
                    originalAmount: parsed.originalAmount, splitCount: parsed.splitCount,
                    isOutsideBudget: parsed.isOutsideBudget
                ))
            case .loan(let person, let amount):
                return .loan(person: person, amount: amount)
            case .question:
                return nil
            }
        }
        guard !items.isEmpty else { return nil }
        return record(items, in: RecordContext(rawText: text, date: now))
    }

    func undo(_ batch: SavedBatch) {
        let batchID = batch.batchID
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.batchID == batchID }))) ?? []
        expenses.forEach(context.delete)
        let loanIDs = batch.loanIDs
        if !loanIDs.isEmpty {
            let loans = (try? context.fetch(FetchDescriptor<Loan>(predicate: #Predicate { loanIDs.contains($0.id) }))) ?? []
            loans.forEach(context.delete)
        }
        commit()
    }

    func delete(_ expense: Expense) {
        context.delete(expense)
        commit()
    }

    /// Lưu luật danh mục cho một tên khoản.
    func teach(name: String, categoryKey: String) {
        let keyword = TextNormalizer.keyword(name)
        guard !keyword.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.keyword == keyword }))) ?? []
        if let rule = existing.first {
            rule.categoryKey = categoryKey
            rule.updatedAt = Date()
        } else {
            context.insert(CategoryRule(keyword: keyword, categoryKey: categoryKey))
        }
    }

    func rules() -> [String: String] {
        ((try? context.fetch(FetchDescriptor<CategoryRule>())) ?? []).lookup
    }

    func expenses(since start: Date) -> [Expense] {
        (try? context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []
    }

    func status(monthlyBudget: Int, now: Date, calendar: Calendar) -> BudgetStatus {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return BudgetCalculator.status(
            monthlyBudget: monthlyBudget,
            entries: expenses(since: start).map(\.budgetEntry),
            now: now, calendar: calendar
        )
    }

    /// Lưu xuống đĩa và báo widget vẽ lại.
    func commit() {
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func summary(of items: [RecordItem]) -> String {
        if items.count == 1, let item = items.first {
            switch item {
            case .expense(let draft):
                let name = draft.name.isEmpty ? String(localized: "khoản chi") : draft.name
                return String(localized: "Đã ghi \(name) \(MoneyFormatter.short(draft.amount))")
            case .loan(let person, let amount):
                return String(localized: "Đã ghi ứng cho \(person) \(MoneyFormatter.short(amount))")
            }
        }
        let total = items.reduce(0) { sum, item in
            switch item {
            case .expense(let draft): sum + draft.amount
            case .loan(_, let amount): sum + amount
            }
        }
        return String(localized: "Đã ghi \(items.count) khoản \(MoneyFormatter.short(total))")
    }
}
