import Foundation
import Testing
@testable import Xu

struct BudgetCalculatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func status(_ today: [BudgetEntry], yesterday: Int = 0) -> BudgetStatus {
        var entries = [BudgetEntry(amount: 1_800_000, date: date(3))] + today
        if yesterday > 0 { entries.append(BudgetEntry(amount: yesterday, date: date(7, hour: 20))) }
        return BudgetCalculator.status(monthlyBudget: 9_000_000, entries: entries, now: date(8), calendar: calendar)
    }

    private func today(_ amount: Int, outside: Bool = false) -> BudgetEntry {
        BudgetEntry(amount: amount, date: date(8, hour: 9), isOutsideBudget: outside)
    }

    @Test func firstExpenseOfTheDay() {
        let status = status([today(106_000)])
        #expect(status.daysLeft == 24)
        #expect(status.allowanceToday == 300_000)
        #expect(status.remainingToday == 194_000)
    }

    @Test func outsideBudgetIsIgnored() {
        let status = status([today(106_000), today(135_000), today(1_200_000, outside: true)])
        #expect(status.remainingToday == 59_000)
    }

    @Test func overTheAllowance() {
        let status = status([today(106_000), today(135_000), today(1_200_000, outside: true), today(115_000)])
        #expect(status.remainingToday == -56_000)
        #expect(status.allowanceTomorrow == 297_000)
        #expect(status.todayFraction == 0)
    }

    @Test func backdatedExpenseLowersTodayAllowance() {
        let status = status([today(106_000)], yesterday: 187_000)
        #expect(status.allowanceToday == 292_000)
        #expect(status.remainingToday == 186_000)
    }

    @Test func lastDayOfMonthHasNoTomorrow() {
        let status = BudgetCalculator.status(
            monthlyBudget: 9_000_000,
            entries: [BudgetEntry(amount: 8_500_000, date: date(10)), BudgetEntry(amount: 100_000, date: date(31, hour: 8))],
            now: date(31), calendar: calendar
        )
        #expect(status.daysLeft == 1)
        #expect(status.allowanceToday == 500_000)
        #expect(status.remainingToday == 400_000)
        #expect(status.allowanceTomorrow == nil)
    }

    @Test func twentyEightDayMonth() {
        let status = BudgetCalculator.status(monthlyBudget: 2_800_000, entries: [], now: date(1, month: 2), calendar: calendar)
        #expect(status.daysLeft == 28)
        #expect(status.allowanceToday == 100_000)
        #expect(status.allowanceTomorrow == 103_000)
    }

    @Test func otherMonthsAndFutureAreIgnored() {
        let entries = [
            BudgetEntry(amount: 500_000, date: date(30, month: 9)),
            BudgetEntry(amount: 500_000, date: date(9)),
        ]
        let status = BudgetCalculator.status(monthlyBudget: 9_000_000, entries: entries, now: date(8), calendar: calendar)
        #expect(status.spentThisMonth == 0)
    }

    @Test func negativeAllowanceRoundsDown() {
        #expect(BudgetCalculator.floorToThousand(-1_500) == -2_000)
        #expect(BudgetCalculator.floorToThousand(292_208) == 292_000)
    }

    @Test func forecastKeepsThePace() {
        let status = status([today(106_000)])
        let forecast = BudgetCalculator.forecast(for: status, now: date(8), calendar: calendar)
        #expect(forecast.pacePerDay == 238_250)
        #expect(forecast.projectedLeftover == 9_000_000 - 1_906_000 - 238_250 * 23)
    }

    @Test func dailyAverageForOnboarding() {
        #expect(BudgetCalculator.dailyAverage(monthlyBudget: 9_000_000, now: date(8), calendar: calendar) == 290_000)
    }

    @Test func previousDays() {
        let entries = [
            BudgetEntry(amount: 268_000, date: date(7)),
            BudgetEntry(amount: 1_000_000, date: date(7), isOutsideBudget: true),
            BudgetEntry(amount: 90_000, date: date(5)),
        ]
        let totals = BudgetCalculator.previousDayTotals(entries: entries, days: 3, now: date(8), calendar: calendar)
        #expect(totals.map(\.total) == [268_000, 0, 90_000])
    }
}
