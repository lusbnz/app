import Foundation
import SwiftData
import Testing
@testable import Xu

struct CategoryBudgetCalculatorTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    private func record(_ category: String, _ amount: Int, outside: Bool = false, date: Date? = nil) -> SpendingRecord {
        SpendingRecord(name: "x", amount: amount, categoryKey: category, date: date ?? now, isOutsideBudget: outside)
    }

    @Test func levelBoundaries() {
        #expect(CategoryBudgetCalculator.level(spent: 0, limit: 1_000) == .ok)
        #expect(CategoryBudgetCalculator.level(spent: 799, limit: 1_000) == .ok)
        #expect(CategoryBudgetCalculator.level(spent: 800, limit: 1_000) == .near)
        #expect(CategoryBudgetCalculator.level(spent: 1_000, limit: 1_000) == .near)
        #expect(CategoryBudgetCalculator.level(spent: 1_001, limit: 1_000) == .over)
        #expect(CategoryBudgetCalculator.level(spent: 5_000, limit: 0) == .ok)
    }

    @Test func statusesCountOnlyThisMonthsInBudgetSpending() {
        let records = [
            record("food", 400_000),
            record("food", 100_000, outside: true),
            record("food", 900_000, date: TestClock.date(2026, 9, 30)),
            record("transport", 50_000),
        ]
        let statuses = CategoryBudgetCalculator.statuses(
            limits: ["food": 500_000, "transport": 200_000, "fun": 300_000], records: records, now: now, calendar: calendar
        )
        #expect(statuses.map(\.key) == ["food", "transport", "fun"])
        #expect(statuses.first?.spent == 400_000)
        #expect(statuses.first?.level == .near)
        #expect(statuses.last?.spent == 0)
        #expect(statuses.last?.level == .ok)
    }

    @Test func statusesSortOverspentByHowFarOver() {
        let statuses = CategoryBudgetCalculator.statuses(
            limits: ["a": 100, "b": 100], records: [record("a", 150), record("b", 300)], now: now, calendar: calendar
        )
        #expect(statuses.map(\.key) == ["b", "a"])
        #expect(statuses.allSatisfy { $0.fraction == 1 })
    }

    @Test func zeroLimitsAreIgnored() {
        let statuses = CategoryBudgetCalculator.statuses(limits: ["food": 0], records: [], now: now, calendar: calendar)
        #expect(statuses.isEmpty)
    }

    @Test func crossingOnlyReportsWorseLevels() {
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 100, added: 100) == nil)
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 700, added: 100) == .near)
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 850, added: 50) == nil)
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 850, added: 200) == .over)
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 1_200, added: 50) == nil)
        #expect(CategoryBudgetCalculator.crossing(limit: 1_000, spentBefore: 100, added: 1_500) == .over)
    }
}

@MainActor
struct CategoryLimitRecorderTests {
    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    private func draft(_ name: String, _ amount: Int, _ category: String = "food", outside: Bool = false, date: Date? = nil) -> RecordItem {
        .expense(ExpenseDraft(name: name, amount: amount, categoryKey: category, isOutsideBudget: outside, date: date))
    }

    @Test func setLimitInsertsUpdatesAndRemoves() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.setLimit(categoryKey: "food", amount: 2_000_000)
        #expect(recorder.limits() == ["food": 2_000_000])
        recorder.setLimit(categoryKey: "food", amount: 3_000_000)
        #expect(recorder.limits() == ["food": 3_000_000])
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).count == 1)
        recorder.setLimit(categoryKey: "food", amount: nil)
        #expect(recorder.limits().isEmpty)
    }

    @Test func recordingWarnsWhenCrossingNearThenOverButNotWhenQuiet() {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.setLimit(categoryKey: "food", amount: 1_000_000)

        #expect(recorder.record([draft("phở", 100_000)]).warning == nil)
        let near = recorder.record([draft("nhậu", 750_000)])
        #expect(near.warning?.contains("85%") == true)
        #expect(recorder.record([draft("cơm", 10_000)]).warning == nil)
        let over = recorder.record([draft("lẩu", 300_000)])
        #expect(over.warning?.contains("vượt hạn mức") == true)
    }

    @Test func outsideBudgetAndOtherCategoriesAndOldDatesDoNotWarn() {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.setLimit(categoryKey: "food", amount: 100_000)
        let longAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())

        #expect(recorder.record([draft("tiệc", 500_000, outside: true)]).warning == nil)
        #expect(recorder.record([draft("grab", 500_000, "transport")]).warning == nil)
        #expect(recorder.record([draft("cũ", 500_000, date: longAgo)]).warning == nil)
    }

    @Test func deletingACategoryRemovesItsLimit() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let category = try #require(try? recorder.addCategory(name: "thú cưng", existing: []).get())
        recorder.setLimit(categoryKey: category.key, amount: 500_000)
        recorder.setLimit(categoryKey: "food", amount: 1_000_000)
        recorder.deleteCategory(category)
        #expect(recorder.limits() == ["food": 1_000_000])
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).count == 1)
    }
}
