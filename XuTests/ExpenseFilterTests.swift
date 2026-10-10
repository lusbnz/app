import Foundation
import Testing
@testable import Xu

struct ExpenseFilterTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    private func record(_ name: String, _ category: String = "food", date: Date? = nil) -> SpendingRecord {
        SpendingRecord(name: name, amount: 45_000, categoryKey: category, date: date ?? now)
    }

    private func matches(_ filter: ExpenseFilter, _ record: SpendingRecord) -> Bool {
        filter.matches(record, calendar: calendar)
    }

    @Test func emptyFilterMatchesEverythingAndIsInactive() {
        let filter = ExpenseFilter()
        #expect(!filter.isActive)
        #expect(matches(filter, record("phở")))
    }

    @Test func blankTextIsInactive() {
        #expect(!ExpenseFilter(text: "   ").isActive)
    }

    @Test func textIgnoresCaseAndAccents() {
        #expect(matches(ExpenseFilter(text: "pho"), record("Phở bò")))
        #expect(matches(ExpenseFilter(text: "PHỞ"), record("pho")))
        #expect(!matches(ExpenseFilter(text: "bún"), record("phở")))
    }

    @Test func everyWordMustAppear() {
        #expect(matches(ExpenseFilter(text: "cơm tấm"), record("cơm tấm sườn")))
        #expect(!matches(ExpenseFilter(text: "cơm gà"), record("cơm tấm")))
    }

    @Test func partialWordMatches() {
        #expect(matches(ExpenseFilter(text: "cà ph"), record("cà phê sữa")))
    }

    @Test func categoriesMatchAnyOfTheSelected() {
        let filter = ExpenseFilter(categoryKeys: ["food", "transport"])
        #expect(matches(filter, record("phở", "food")))
        #expect(matches(filter, record("grab", "transport")))
        #expect(!matches(filter, record("áo", "shopping")))
    }

    @Test func rangeIncludesBothEndDays() {
        let filter = ExpenseFilter(from: TestClock.date(2026, 10, 5, 0), to: TestClock.date(2026, 10, 7, 0))
        #expect(matches(filter, record("a", date: TestClock.date(2026, 10, 5, 0))))
        #expect(matches(filter, record("a", date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 23, minute: 59)))))
        #expect(!matches(filter, record("a", date: TestClock.date(2026, 10, 4, 23))))
        #expect(!matches(filter, record("a", date: TestClock.date(2026, 10, 8, 0))))
    }

    @Test func openEndedRanges() {
        let since = ExpenseFilter(from: TestClock.date(2026, 10, 5))
        #expect(matches(since, record("a", date: TestClock.date(2026, 12, 1))))
        #expect(!matches(since, record("a", date: TestClock.date(2026, 10, 4))))
        let until = ExpenseFilter(to: TestClock.date(2026, 10, 5))
        #expect(matches(until, record("a", date: TestClock.date(2025, 1, 1))))
        #expect(!matches(until, record("a", date: TestClock.date(2026, 10, 6))))
    }

    @Test func conditionsCombine() {
        let filter = ExpenseFilter(text: "pho", categoryKeys: ["food"], from: TestClock.date(2026, 10, 1))
        #expect(matches(filter, record("phở", "food")))
        #expect(!matches(filter, record("phở", "other")))
        #expect(!matches(filter, record("phở", "food", date: TestClock.date(2026, 9, 30))))
    }

    @Test func thisMonthPresetCoversWholeMonth() {
        var filter = ExpenseFilter()
        filter.apply(.thisMonth, now: now, calendar: calendar)
        #expect(filter.isActive)
        #expect(matches(filter, record("a", date: TestClock.date(2026, 10, 1, 0))))
        #expect(matches(filter, record("a", date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30)))))
        #expect(!matches(filter, record("a", date: TestClock.date(2026, 9, 30, 23))))
        #expect(!matches(filter, record("a", date: TestClock.date(2026, 11, 1, 0))))
    }

    @Test func lastMonthPresetAcrossYearBoundary() {
        var filter = ExpenseFilter()
        filter.apply(.lastMonth, now: TestClock.date(2026, 1, 15), calendar: calendar)
        #expect(matches(filter, record("a", date: TestClock.date(2025, 12, 31))))
        #expect(!matches(filter, record("a", date: TestClock.date(2026, 1, 1))))
    }

    @Test func allPresetClearsRangeAndCustomKeepsIt() {
        var filter = ExpenseFilter(from: TestClock.date(2026, 10, 1), to: TestClock.date(2026, 10, 5))
        filter.apply(.custom, now: now, calendar: calendar)
        #expect(filter.from != nil && filter.to != nil)
        filter.apply(.all, now: now, calendar: calendar)
        #expect(filter.from == nil && filter.to == nil)
    }

    @Test func textAlsoMatchesPlaceNameAndCurrency() {
        let record = SpendingRecord(
            name: "cơm", amount: 400_000, categoryKey: "food", date: now, placeName: "Quán Hải Sản Bà Hai", foreignCode: "usd"
        )
        #expect(matches(ExpenseFilter(text: "hai san"), record))
        #expect(matches(ExpenseFilter(text: "com bà"), record))        // từ ở tên khoản lẫn tên nơi
        #expect(matches(ExpenseFilter(text: "USD"), record))
        #expect(!matches(ExpenseFilter(text: "cà phê"), record))
        #expect(!matches(ExpenseFilter(text: "hai san"), SpendingRecord(name: "cơm", amount: 1, categoryKey: "food", date: now)))
    }

    @Test func currencyFilterKeepsOnlyMatchingForeignExpenses() {
        let dollars = SpendingRecord(name: "vé", amount: 500_000, categoryKey: "fun", date: now, foreignCode: "usd")
        let euros = SpendingRecord(name: "vé", amount: 600_000, categoryKey: "fun", date: now, foreignCode: "eur")
        let dong = SpendingRecord(name: "vé", amount: 50_000, categoryKey: "fun", date: now)
        let filter = ExpenseFilter(currencies: ["usd"])
        #expect(filter.isActive)
        #expect(matches(filter, dollars))
        #expect(!matches(filter, euros))
        #expect(!matches(filter, dong))
        #expect(matches(ExpenseFilter(currencies: ["usd", "eur"]), euros))
        #expect(matches(ExpenseFilter(), dong))
    }
}
