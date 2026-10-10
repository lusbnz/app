import Foundation
import Testing
@testable import Xu

struct HistoryWindowTests {
    private let calendar = TestClock.calendar

    @Test func initialStartIsAWeekStartAtLeastFourWeeksBack() {
        let now = TestClock.now          // 9/10/2026
        let start = HistoryWindow.initialStart(now: now, calendar: calendar)
        #expect(start == HistoryWindow.weekStart(of: start, calendar: calendar))
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        #expect(days >= 28 && days <= 34)
    }

    @Test func initialStartAlwaysCoversTheCurrentMonth() {
        for day in [1, 9, 15, 31] {
            let now = TestClock.date(2026, 10, day)
            let start = HistoryWindow.initialStart(now: now, calendar: calendar)
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            #expect(start <= monthStart, "ngày \(day)")
        }
    }

    @Test func nextStartMovesToTheWeekOfTheOldestFetchedDate() {
        let current = HistoryWindow.weekStart(of: TestClock.date(2026, 9, 14), calendar: calendar)
        let older = [TestClock.date(2026, 9, 10), TestClock.date(2026, 8, 20), TestClock.date(2026, 9, 1)]
        let next = HistoryWindow.nextStart(olderDates: older, currentStart: current, calendar: calendar)
        #expect(next == HistoryWindow.weekStart(of: TestClock.date(2026, 8, 20), calendar: calendar))
        #expect(HistoryWindow.nextStart(olderDates: [], currentStart: current, calendar: calendar) == nil)
    }

    @Test func nextStartAlwaysMakesProgress() {
        let current = HistoryWindow.weekStart(of: TestClock.date(2026, 9, 14), calendar: calendar)
        // Khoản "cũ hơn" nhưng cùng tuần (không nên xảy ra) vẫn phải lùi được ít nhất một tuần.
        let next = HistoryWindow.nextStart(olderDates: [current], currentStart: current, calendar: calendar)
        #expect((next ?? current) < current)
    }

    @Test func startIncludingADayOnlyMovesBackwards() {
        let current = HistoryWindow.weekStart(of: TestClock.date(2026, 9, 14), calendar: calendar)
        #expect(HistoryWindow.start(including: TestClock.date(2026, 9, 20), currentStart: current, calendar: calendar) == current)
        let early = HistoryWindow.start(including: TestClock.date(2026, 7, 3), currentStart: current, calendar: calendar)
        #expect(early == HistoryWindow.weekStart(of: TestClock.date(2026, 7, 3), calendar: calendar))
    }
}

struct WeekSummaryTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now       // thứ Sáu 9/10/2026

    private func record(_ amount: Int, _ date: Date, outside: Bool = false) -> SpendingRecord {
        SpendingRecord(name: "x", amount: amount, categoryKey: "food", date: date, isOutsideBudget: outside)
    }

    @Test func totalsAreGroupedByWeekAndFlagTheCurrentWeek() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        let summaries = WeekSummaries.make(records: [
            record(100_000, thisWeek.addingTimeInterval(3_600)),
            record(50_000, now),
            record(300_000, lastWeek.addingTimeInterval(3_600)),
        ], now: now, calendar: calendar)
        #expect(summaries.count == 2)
        #expect(summaries[thisWeek]?.total == 150_000)
        #expect(summaries[thisWeek]?.isCurrent == true)
        #expect(summaries[lastWeek]?.total == 300_000)
        #expect(summaries[lastWeek]?.isCurrent == false)
    }

    @Test func pastWeekComparesWithTheWholePreviousWeek() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        let before = HistoryWindow.comparisonStart(for: lastWeek, calendar: calendar)
        let summaries = WeekSummaries.make(records: [
            record(300_000, lastWeek.addingTimeInterval(3_600)),
            record(120_000, before.addingTimeInterval(3_600)),
            record(80_000, before.addingTimeInterval(6 * 86_400)),
        ], now: now, calendar: calendar)
        let summary = summaries[lastWeek]
        #expect(summary?.previousTotal == 200_000)
        #expect(summary?.delta == 100_000)
        #expect(summary?.hasPrevious == true)
    }

    @Test func currentWeekComparesOnlyTheSameElapsedDays() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        let elapsed = calendar.dateComponents([.day], from: thisWeek, to: calendar.startOfDay(for: now)).day ?? 0
        let sameSpan = lastWeek.addingTimeInterval(3_600)                                     // ngày đầu tuần trước
        let laterThanSpan = calendar.date(byAdding: .day, value: elapsed + 1, to: lastWeek)!    // sau đoạn tương ứng
        let summaries = WeekSummaries.make(records: [
            record(100_000, thisWeek.addingTimeInterval(3_600)),
            record(70_000, sameSpan),
            record(900_000, laterThanSpan.addingTimeInterval(3_600)),
        ], now: now, calendar: calendar)
        #expect(summaries[thisWeek]?.previousTotal == 70_000)
    }

    @Test func noPreviousDataMeansNothingToCompare() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let summaries = WeekSummaries.make(records: [record(10_000, thisWeek.addingTimeInterval(3_600))], now: now, calendar: calendar)
        #expect(summaries[thisWeek]?.hasPrevious == false)
    }

    @Test func outsideBudgetItemsKeepTheWeekButNotTheTotal() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let summaries = WeekSummaries.make(records: [record(5_000_000, thisWeek.addingTimeInterval(3_600), outside: true)], now: now, calendar: calendar)
        #expect(summaries[thisWeek]?.total == 0)
    }
}

struct DayIndexTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    @Test func startsWithTodayAndListsEachPastDayOnce() {
        let dates = [TestClock.date(2026, 10, 8, 9), TestClock.date(2026, 10, 8, 20), TestClock.date(2026, 10, 3), TestClock.date(2026, 10, 9, 10)]
        let days = DayIndex.days(from: dates, now: now, calendar: calendar)
        #expect(days == [TestClock.date(2026, 10, 9, 0), TestClock.date(2026, 10, 8, 0), TestClock.date(2026, 10, 3, 0)].map { calendar.startOfDay(for: $0) })
    }

    @Test func emptyHistoryStillHasToday() {
        #expect(DayIndex.days(from: [], now: now, calendar: calendar).count == 1)
    }

    @Test func fractionMapsToDays() {
        let days = (0..<5).map { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now))! }
        #expect(DayIndex.day(atFraction: 0, in: days) == days[0])
        #expect(DayIndex.day(atFraction: 1, in: days) == days[4])
        #expect(DayIndex.day(atFraction: 0.5, in: days) == days[2])
        #expect(DayIndex.day(atFraction: -3, in: days) == days[0])
        #expect(DayIndex.day(atFraction: 9, in: days) == days[4])
        #expect(DayIndex.day(atFraction: 0.5, in: []) == nil)
    }

    @Test func fractionOfADayIsTheInverse() {
        let days = (0..<5).map { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now))! }
        for (index, day) in days.enumerated() {
            #expect(DayIndex.fraction(of: day, in: days) == Double(index) / 4)
        }
        #expect(DayIndex.fraction(of: days[0], in: [days[0]]) == 0)
    }
}

struct WeekTitleTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now       // 9/10/2026

    @Test func thisWeekAndLastWeekGetNames() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        #expect(VietnameseDate.weekTitle(start: thisWeek, now: now, calendar: calendar) == "Tuần này")
        #expect(VietnameseDate.weekTitle(start: lastWeek, now: now, calendar: calendar) == "Tuần trước")
    }

    @Test func olderWeeksShowTheirDateRange() {
        let start = HistoryWindow.weekStart(of: TestClock.date(2026, 9, 16), calendar: calendar)
        let title = VietnameseDate.weekTitle(start: start, now: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start)!
        let startParts = calendar.dateComponents([.day, .month], from: start)
        let endParts = calendar.dateComponents([.day, .month], from: end)
        #expect(title == "\(startParts.day!)/\(startParts.month!) – \(endParts.day!)/\(endParts.month!)")
    }

    @Test func weeksInOtherYearsShowTheYear() {
        let start = HistoryWindow.weekStart(of: TestClock.date(2025, 12, 17), calendar: calendar)
        #expect(VietnameseDate.weekTitle(start: start, now: now, calendar: calendar).contains("2025"))
    }

    @Test func scrubLabelIsRelativeForARecentWeekThenADate() {
        #expect(VietnameseDate.scrubLabel(now, now: now, calendar: calendar) == "hôm nay")
        #expect(VietnameseDate.scrubLabel(TestClock.date(2026, 9, 29), now: now, calendar: calendar) == "29 tháng 9")
        #expect(VietnameseDate.scrubLabel(TestClock.date(2025, 3, 5), now: now, calendar: calendar) == "5 tháng 3, 2025")
    }
}

struct WeekDaysTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now       // thứ Sáu 9/10/2026

    private func record(_ amount: Int, _ date: Date, outside: Bool = false) -> SpendingRecord {
        SpendingRecord(name: "x", amount: amount, categoryKey: "food", date: date, isOutsideBudget: outside)
    }

    @Test func listsSevenDaysAndFlagsTodayAndTheFuture() {
        let week = HistoryWindow.weekStart(of: now, calendar: calendar)
        let days = WeekDays.make(records: [], weekStart: week, now: now, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first?.day == calendar.startOfDay(for: week))
        #expect(days.filter(\.isToday).count == 1)
        #expect(days.first(where: \.isToday)?.day == calendar.startOfDay(for: now))
        #expect(days.filter(\.isFuture).allSatisfy { $0.day > calendar.startOfDay(for: now) })
        #expect(!days.filter(\.isFuture).isEmpty)
    }

    @Test func sumsInBudgetSpendingPerDay() {
        let week = HistoryWindow.weekStart(of: now, calendar: calendar)
        let monday = week.addingTimeInterval(3_600)
        let days = WeekDays.make(records: [
            record(40_000, monday), record(60_000, monday.addingTimeInterval(7_200)),
            record(9_000_000, monday, outside: true),
        ], weekStart: week, now: now, calendar: calendar)
        #expect(days[0].total == 100_000)
        #expect(days[1].total == 0)
    }

    @Test func comparisonReferenceIsTodayForThisWeekAndTheLastDayOtherwise() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        #expect(WeekDays.comparisonReference(weekStart: thisWeek, now: now, calendar: calendar) == now)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        let reference = WeekDays.comparisonReference(weekStart: lastWeek, now: now, calendar: calendar)
        #expect(HistoryWindow.weekStart(of: reference, calendar: calendar) == lastWeek)
        #expect(calendar.dateComponents([.day], from: lastWeek, to: calendar.startOfDay(for: reference)).day == 6)
    }

    @Test func pastWeekComparesWholeWeeksThroughPeriodComparison() {
        let thisWeek = HistoryWindow.weekStart(of: now, calendar: calendar)
        let lastWeek = HistoryWindow.comparisonStart(for: thisWeek, calendar: calendar)
        let before = HistoryWindow.comparisonStart(for: lastWeek, calendar: calendar)
        let records = [
            record(300_000, lastWeek.addingTimeInterval(3_600)),
            record(100_000, before.addingTimeInterval(3_600)),
            record(80_000, before.addingTimeInterval(6 * 86_400 + 3_600)),    // ngày cuối tuần trước nữa
        ]
        let reference = WeekDays.comparisonReference(weekStart: lastWeek, now: now, calendar: calendar)
        let result = PeriodComparison.make(records: records, period: .week, now: reference, calendar: calendar)
        #expect(result.currentTotal == 300_000)
        #expect(result.previousTotal == 180_000)              // cả tuần, không cắt ở "hôm nay"
    }
}
