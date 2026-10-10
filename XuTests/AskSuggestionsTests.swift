import Foundation
import Testing
@testable import Xu

struct AskSuggestionsTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    private func snapshot(_ records: [SpendingRecord], budget: Int = 9_000_000) -> SpendingSnapshot {
        SpendingSnapshot.make(records: records, monthlyBudget: budget, now: now, calendar: calendar)
    }

    private func record(_ name: String, _ amount: Int, _ category: String, day: Int, outside: Bool = false) -> SpendingRecord {
        SpendingRecord(name: name, amount: amount, categoryKey: category, date: TestClock.date(2026, 10, day), isOutsideBudget: outside)
    }

    private func title(_ key: String) -> String { key == "food" ? "ăn uống" : key == "transport" ? "đi lại" : key }

    @Test func withDataTheFirstQuestionsMentionRealCategoriesAndNames() {
        let result = AskSuggestions.make(snapshot: snapshot([
            record("phở", 45_000, "food", day: 2), record("phở", 50_000, "food", day: 3),
            record("grab", 32_000, "transport", day: 3), record("cf", 29_000, "food", day: 5),
        ]), categoryTitle: title)
        #expect(result.count == 4)
        #expect(result[0] == "Tháng này ăn uống hết bao nhiêu?")
        #expect(result[1] == "Phở tháng này mấy lần?")
        #expect(result.contains("Ngày nào tiêu nhiều nhất?"))
        #expect(result.contains("Tháng này còn lại bao nhiêu?"))
    }

    @Test func emptyMonthStillOffersTheRemainingQuestion() {
        #expect(AskSuggestions.make(snapshot: snapshot([]), categoryTitle: title) == ["Tháng này còn lại bao nhiêu?"])
    }

    @Test func noBudgetMeansNoRemainingQuestion() {
        #expect(AskSuggestions.make(snapshot: snapshot([], budget: 0), categoryTitle: title).isEmpty)
    }

    @Test func outsideBudgetQuestionOnlyWhenThereIsSuchSpending() {
        let with = AskSuggestions.make(snapshot: snapshot([
            record("phở", 45_000, "food", day: 2), record("sửa xe", 3_000_000, "transport", day: 3, outside: true),
        ]), categoryTitle: title, limit: 10)
        #expect(with.contains("Các khoản ngoài ngân sách là bao nhiêu?"))
        let without = AskSuggestions.make(snapshot: snapshot([record("phở", 45_000, "food", day: 2)]), categoryTitle: title, limit: 10)
        #expect(!without.contains("Các khoản ngoài ngân sách là bao nhiêu?"))
    }

    @Test func nameQuestionSkipsANameThatIsJustTheCategory() {
        let result = AskSuggestions.make(snapshot: snapshot([
            record("ăn uống", 100_000, "food", day: 2), record("grab", 32_000, "transport", day: 3),
        ]), categoryTitle: title, limit: 10)
        #expect(!result.contains("Ăn uống tháng này mấy lần?"))
    }

    @Test func limitIsRespected() {
        let result = AskSuggestions.make(snapshot: snapshot([
            record("phở", 45_000, "food", day: 2), record("grab", 32_000, "transport", day: 3),
        ]), categoryTitle: title, limit: 2)
        #expect(result.count == 2)
    }
}
