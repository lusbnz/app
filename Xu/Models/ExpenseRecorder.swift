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

    /// App gắn vào đây để làm việc sau mỗi lần ghi xuống đĩa (xếp lại lịch nhắc). Ở widget thì để trống.
    static var afterCommit: (@MainActor () -> Void)?

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
        SaveGate.didSave(now: Date(), calendar: .current)
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
        SaveGate.didUndo(now: Date(), calendar: .current)
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

    // MARK: - Danh mục và luật

    /// Thêm danh mục tự thêm. `existing` là mọi tên đang có, gồm cả danh mục có sẵn.
    @discardableResult
    func addCategory(name: String, existing: [String]) -> Result<CustomCategory, CategoryNaming.Failure> {
        switch CategoryNaming.validate(name, existing: existing) {
        case .success(let cleaned):
            let category = CustomCategory(name: cleaned)
            context.insert(category)
            commit()
            return .success(category)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    func renameCategory(_ category: CustomCategory, to name: String, existing: [String]) -> Result<Void, CategoryNaming.Failure> {
        let others = existing.filter { TextNormalizer.keyword($0) != TextNormalizer.keyword(category.name) }
        switch CategoryNaming.validate(name, existing: others) {
        case .success(let cleaned):
            category.name = cleaned
            commit()
            return .success(())
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// Xóa danh mục: khoản chi đã gán chuyển về "khác", luật trỏ tới nó bị xóa.
    func deleteCategory(_ category: CustomCategory) {
        let key = category.key
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.categoryKey == key }))) ?? []
        expenses.forEach { $0.categoryKey = SpendingCategory.other.rawValue }
        let rules = (try? context.fetch(FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.categoryKey == key }))) ?? []
        rules.forEach(context.delete)
        context.delete(category)
        commit()
    }

    /// Thêm hoặc đổi luật theo từ khóa. Trả về false khi từ khóa rỗng.
    @discardableResult
    func setRule(keyword: String, categoryKey: String) -> Bool {
        guard !TextNormalizer.keyword(keyword).isEmpty else { return false }
        teach(name: keyword, categoryKey: categoryKey)
        commit()
        return true
    }

    func deleteRule(_ rule: CategoryRule) {
        context.delete(rule)
        commit()
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
        Self.afterCommit?()
    }

    /// Đã ghi khoản nào trong ngày `now` chưa (tính theo lúc ghi, không theo ngày phát sinh).
    func hasLogged(on now: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: now)
        let count = (try? context.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.createdAt >= start }))) ?? 0
        return count > 0
    }

    /// Ghi một khoản biết sẵn tên và số tiền (gợi ý, nút widget, thông báo).
    @discardableResult
    func recordQuick(
        name: String, amount: Int, monthlyBudget: Int, now: Date, calendar: Calendar, coordinate: Coordinate? = nil
    ) -> SavedBatch {
        let allowance = status(monthlyBudget: monthlyBudget, now: now, calendar: calendar).allowanceToday
        let draft = ExpenseDraft(
            name: name, amount: amount,
            categoryKey: CategoryClassifier.categoryKey(for: name, rules: rules()),
            isOutsideBudget: ExpenseParser.isOutsideBudget(amount: amount, dailyAllowance: allowance)
        )
        return record([.expense(draft)], in: RecordContext(
            rawText: name, date: now, latitude: coordinate?.latitude, longitude: coordinate?.longitude
        ))
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
