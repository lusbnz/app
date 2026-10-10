import Foundation
import Testing
@testable import Xu

struct DayLoadTests {
    @Test func noAllowanceMeansNoBar() {
        #expect(DayLoad.make(spent: 100_000, allowance: 0) == nil)
        #expect(DayLoad.make(spent: 100_000, allowance: -5_000) == nil)
    }

    @Test func fractionFollowsSpendingUpToTheAllowance() {
        #expect(DayLoad.make(spent: 0, allowance: 300_000) == DayLoad(fraction: 0, isOver: false))
        #expect(DayLoad.make(spent: 150_000, allowance: 300_000) == DayLoad(fraction: 0.5, isOver: false))
        #expect(DayLoad.make(spent: 300_000, allowance: 300_000) == DayLoad(fraction: 1, isOver: false))
    }

    @Test func overspendingFillsTheBarAndFlagsIt() {
        #expect(DayLoad.make(spent: 300_001, allowance: 300_000) == DayLoad(fraction: 1, isOver: true))
        #expect(DayLoad.make(spent: 900_000, allowance: 300_000) == DayLoad(fraction: 1, isOver: true))
    }

    @Test func pastDayAllowanceUsesThatMonthsLength() {
        let calendar = TestClock.calendar
        let october = DayLoad.pastDayAllowance(monthlyBudget: 9_300_000, day: TestClock.date(2026, 10, 3), calendar: calendar)
        let september = DayLoad.pastDayAllowance(monthlyBudget: 9_300_000, day: TestClock.date(2026, 9, 3), calendar: calendar)
        #expect(october == 300_000)        // 31 ngày
        #expect(september == 310_000)      // 30 ngày
    }
}
