import Foundation
import Testing
@testable import Xu

struct PeriodComparisonTests {
    private let calendar = TestClock.calendar
    // 9/10/2026 là thứ Sáu; tuần bắt đầu từ thứ Hai 5/10 hoặc Chủ nhật 4/10 tùy lịch.
    private let now = TestClock.now

    private func record(_ category: String, _ amount: Int, _ day: Int, month: Int = 10, outside: Bool = false) -> SpendingRecord {
        SpendingRecord(name: "x", amount: amount, categoryKey: category, date: TestClock.date(2026, month, day), isOutsideBudget: outside)
    }

    @Test func comparesMonthToSameDaysOfPreviousMonth() {
        let records = [
            record("food", 300_000, 3), record("food", 100_000, 9),
            record("food", 200_000, 5, month: 9),
            record("food", 900_000, 20, month: 9),          // sau ngày 9 của tháng trước: không tính
            record("transport", 50_000, 2, month: 9),
        ]
        let result = PeriodComparison.make(records: records, period: .month, now: now, calendar: calendar)
        let food = result.changes.first { $0.key == "food" }
        #expect(food?.current == 400_000)
        #expect(food?.previous == 200_000)
        #expect(food?.delta == 200_000)
        #expect(food?.percent == 100)
        #expect(result.currentTotal == 400_000)
        #expect(result.previousTotal == 250_000)
    }

    @Test func includesCategoriesOnlySpentBefore() {
        let records = [record("transport", 50_000, 2, month: 9), record("food", 10_000, 4)]
        let result = PeriodComparison.make(records: records, period: .month, now: now, calendar: calendar)
        let transport = result.changes.first { $0.key == "transport" }
        #expect(transport?.current == 0)
        #expect(transport?.delta == -50_000)
        #expect(transport?.percent == -100)
        #expect(result.changes.first?.key == "transport")   // thay đổi lớn nhất đứng đầu
    }

    @Test func percentIsNilWhenNothingBefore() {
        let result = PeriodComparison.make(records: [record("food", 10_000, 4)], period: .month, now: now, calendar: calendar)
        #expect(result.changes.first?.percent == nil)
    }

    @Test func ignoresOutsideBudget() {
        let records = [record("food", 20_000_000, 4, outside: true), record("food", 10_000, 4)]
        let result = PeriodComparison.make(records: records, period: .month, now: now, calendar: calendar)
        #expect(result.currentTotal == 10_000)
    }

    @Test func comparesWeekToPreviousWeek() {
        let week = ComparisonPeriod.week.interval(containing: now, calendar: calendar)!
        let lastWeek = ComparisonPeriod.week.previousInterval(of: now, calendar: calendar)!
        #expect(lastWeek.end == week.start)
        let thisWeekRecord = SpendingRecord(name: "x", amount: 70_000, categoryKey: "food", date: week.start.addingTimeInterval(3_600))
        let lastWeekRecord = SpendingRecord(name: "x", amount: 40_000, categoryKey: "food", date: lastWeek.start.addingTimeInterval(3_600))
        let result = PeriodComparison.make(records: [thisWeekRecord, lastWeekRecord], period: .week, now: now, calendar: calendar)
        #expect(result.currentTotal == 70_000)
        #expect(result.previousTotal == 40_000)
        #expect(result.delta == 30_000)
    }

    @Test func monthEndOfShortMonthDoesNotOverreach() {
        // 31/10 so với tháng 9 chỉ có 30 ngày: lấy trọn tháng 9, không tràn sang tháng 10.
        let endOfOctober = TestClock.date(2026, 10, 31)
        let records = [record("food", 5_000, 30, month: 9), record("food", 7_000, 1)]
        let result = PeriodComparison.make(records: records, period: .month, now: endOfOctober, calendar: calendar)
        #expect(result.previousTotal == 5_000)
        #expect(result.currentTotal == 7_000)
    }

    @Test func emptyHasNoData() {
        let result = PeriodComparison.make(records: [], period: .week, now: now, calendar: calendar)
        #expect(!result.hasData)
    }
}
