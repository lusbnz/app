import Foundation
import Testing
@testable import Xu

struct SummaryComposerTests {
    private let calendar = TestClock.calendar

    private func record(_ amount: Int, _ category: String, _ date: Date, outside: Bool = false) -> SpendingRecord {
        SpendingRecord(name: "x", amount: amount, categoryKey: category, date: date, isOutsideBudget: outside)
    }

    @Test func weeklySummaryTotalsComparesAndFindsTopCategory() {
        let friday = TestClock.date(2026, 10, 9)
        let week = HistoryWindow.weekStart(of: friday, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: week, calendar: calendar)
        let records = [
            record(300_000, "food", week.addingTimeInterval(3_600)),
            record(100_000, "food", week.addingTimeInterval(90_000)),
            record(150_000, "transport", week.addingTimeInterval(180_000)),
            record(5_000_000, "bills", week.addingTimeInterval(3_600), outside: true),
            record(400_000, "food", lastWeek.addingTimeInterval(3_600)),
        ]
        let summary = SummaryComposer.make(kind: .week, records: records, budget: nil, containing: friday, calendar: calendar)
        #expect(summary?.spent == 550_000)
        #expect(summary?.previousSpent == 400_000)
        #expect(summary?.delta == 150_000)
        #expect(summary?.topCategoryKey == "food")
        #expect(summary?.topCategoryAmount == 400_000)
        #expect(summary?.daysWithSpending == 3)
        #expect(summary?.budget == nil)
    }

    @Test func monthlySummaryHasBudgetAndLeftover() {
        let records = [
            record(2_000_000, "food", TestClock.date(2026, 10, 3)),
            record(500_000, "fun", TestClock.date(2026, 10, 20)),
            record(1_000_000, "food", TestClock.date(2026, 9, 12)),
        ]
        let summary = SummaryComposer.make(
            kind: .month, records: records, budget: .monthly(9_000_000), containing: TestClock.date(2026, 10, 31), calendar: calendar
        )
        #expect(summary?.spent == 2_500_000)
        #expect(summary?.previousSpent == 1_000_000)
        #expect(summary?.budget == 9_000_000)
        #expect(summary?.leftover == 6_500_000)
    }

    @Test func weeklyBudgetBecomesAMonthlyEquivalentForMonthSummaries() {
        let summary = SummaryComposer.make(
            kind: .month, records: [record(100_000, "food", TestClock.date(2026, 10, 3))],
            budget: BudgetSetting(period: .week, amount: 2_100_000), containing: TestClock.date(2026, 10, 31), calendar: calendar
        )
        #expect(summary?.budget == 9_300_000)
    }

    @Test func nothingSpentMeansNoSummary() {
        #expect(SummaryComposer.make(kind: .week, records: [], budget: nil, containing: TestClock.now, calendar: calendar) == nil)
        let onlyOutside = [record(5_000_000, "bills", TestClock.date(2026, 10, 8), outside: true)]
        #expect(SummaryComposer.make(kind: .week, records: onlyOutside, budget: nil, containing: TestClock.now, calendar: calendar) == nil)
    }

    @Test func noPreviousSpendingMeansNothingToCompare() {
        let summary = SummaryComposer.make(
            kind: .week, records: [record(100_000, "food", TestClock.date(2026, 10, 8))], budget: nil, containing: TestClock.now, calendar: calendar
        )
        #expect(summary?.previousSpent == nil && summary?.delta == nil)
    }
}

struct SummaryPlannerTests {
    private let calendar = TestClock.calendar

    @Test func weeklyFiresOnTheLastDayOfTheWeekAtEight() throws {
        let fire = try #require(SummaryPlanner.nextFire(kind: .week, now: TestClock.now, calendar: calendar))
        let week = calendar.dateInterval(of: .weekOfYear, for: TestClock.now)!
        let lastDay = calendar.date(byAdding: .day, value: -1, to: week.end)!
        #expect(calendar.isDate(fire, inSameDayAs: lastDay))
        #expect(calendar.component(.hour, from: fire) == 20 && calendar.component(.minute, from: fire) == 0)
        #expect(fire > TestClock.now)
    }

    @Test func weeklyMovesToNextWeekOnceTonightHasPassed() throws {
        let week = calendar.dateInterval(of: .weekOfYear, for: TestClock.now)!
        let lastDay = calendar.date(byAdding: .day, value: -1, to: week.end)!
        let after = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: lastDay)!
        let fire = try #require(SummaryPlanner.nextFire(kind: .week, now: after, calendar: calendar))
        #expect(fire >= week.end)
        let before = calendar.date(bySettingHour: 19, minute: 59, second: 0, of: lastDay)!
        let sameDay = try #require(SummaryPlanner.nextFire(kind: .week, now: before, calendar: calendar))
        #expect(calendar.isDate(sameDay, inSameDayAs: lastDay))
    }

    @Test func monthlyFiresOnTheLastDayOfTheMonthAtEightFifteen() throws {
        let fire = try #require(SummaryPlanner.nextFire(kind: .month, now: TestClock.now, calendar: calendar))
        #expect(calendar.component(.month, from: fire) == 10 && calendar.component(.day, from: fire) == 31)
        #expect(calendar.component(.hour, from: fire) == 20 && calendar.component(.minute, from: fire) == 15)
    }

    @Test func monthlyRollsOverAfterTheLastEvening() throws {
        let late = TestClock.date(2026, 10, 31, 21)
        let fire = try #require(SummaryPlanner.nextFire(kind: .month, now: late, calendar: calendar))
        #expect(calendar.component(.month, from: fire) == 11 && calendar.component(.day, from: fire) == 30)
    }

    @Test func shortMonthEndsOnItsLastDay() throws {
        let fire = try #require(SummaryPlanner.nextFire(kind: .month, now: TestClock.date(2026, 2, 10), calendar: calendar))
        #expect(calendar.component(.day, from: fire) == 28)
    }
}

struct SummaryTextTests {
    private let calendar = TestClock.calendar
    private let interval = DateInterval(start: TestClock.date(2026, 10, 5, 0), end: TestClock.date(2026, 10, 12, 0))

    private func summary(
        _ kind: SummaryKind, spent: Int, previous: Int?, top: String? = "food", topAmount: Int = 600_000, budget: Int? = nil
    ) -> PeriodSummary {
        PeriodSummary(
            kind: kind,
            interval: kind == .month ? DateInterval(start: TestClock.date(2026, 10, 1, 0), end: TestClock.date(2026, 11, 1, 0)) : interval,
            spent: spent, previousSpent: previous, topCategoryKey: top, topCategoryAmount: topAmount, budget: budget, daysWithSpending: 4
        )
    }

    private func title(_ key: String) -> String { key == "food" ? "ăn uống" : key }

    @Test func weeklyTextMentionsTotalChangeAndTopCategory() {
        let content = SummaryText.compose(summary(.week, spent: 1_200_000, previous: 1_080_000), categoryTitle: title, calendar: calendar)
        #expect(content.title == "Tổng kết tuần")
        #expect(content.body == "Tuần này bạn đã tiêu 1,2tr. Tăng 120k so với tuần trước. Nhiều nhất: ăn uống 600k.")
    }

    @Test func weeklyTextWhenSpendingFellOrStayedTheSame() {
        let down = SummaryText.compose(summary(.week, spent: 900_000, previous: 1_000_000), categoryTitle: title, calendar: calendar)
        #expect(down.body.contains("Giảm 100k so với tuần trước."))
        let same = SummaryText.compose(summary(.week, spent: 900_000, previous: 900_000), categoryTitle: title, calendar: calendar)
        #expect(same.body.contains("Bằng tuần trước."))
    }

    @Test func weeklyTextSkipsTheComparisonWithoutAPreviousWeek() {
        let content = SummaryText.compose(summary(.week, spent: 400_000, previous: nil, top: nil, topAmount: 0), categoryTitle: title, calendar: calendar)
        #expect(content.body == "Tuần này bạn đã tiêu 400k.")
    }

    @Test func monthlyTextReportsLeftoverOrOverspend() {
        let under = SummaryText.compose(
            summary(.month, spent: 7_800_000, previous: 8_100_000, budget: 9_000_000), categoryTitle: title, calendar: calendar
        )
        #expect(under.title == "Tổng kết Tháng 10")
        #expect(under.body.hasPrefix("Đã tiêu 7,8tr trên 9tr, còn dư 1,2tr."))
        #expect(under.body.contains("Giảm 300k so với tháng trước."))
        let over = SummaryText.compose(
            summary(.month, spent: 9_500_000, previous: nil, budget: 9_000_000), categoryTitle: title, calendar: calendar
        )
        #expect(over.body.hasPrefix("Đã tiêu 9,5tr trên 9tr, vượt 500k."))
    }

    @Test func monthlyTextWithoutABudgetJustStatesTheTotal() {
        let content = SummaryText.compose(summary(.month, spent: 3_000_000, previous: nil, top: nil, topAmount: 0), categoryTitle: title, calendar: calendar)
        #expect(content.body == "Tháng này bạn đã tiêu 3tr.")
    }
}
