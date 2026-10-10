import Foundation
import Testing
@testable import Xu

struct WeeklyBudgetTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now                 // thứ Sáu 9/10/2026, 15:00

    private func entry(_ amount: Int, _ date: Date, outside: Bool = false) -> BudgetEntry {
        BudgetEntry(amount: amount, date: date, isOutsideBudget: outside)
    }

    private var weekStart: Date { HistoryWindow.weekStart(of: now, calendar: calendar) }

    @Test func weeklyStatusCountsOnlyTheCurrentWeek() {
        let lastWeek = HistoryWindow.comparisonStart(for: weekStart, calendar: calendar)
        let entries = [
            entry(900_000, lastWeek.addingTimeInterval(3_600)),          // tuần trước: không tính
            entry(200_000, weekStart.addingTimeInterval(3_600)),
            entry(50_000, now),
        ]
        let status = BudgetCalculator.status(budget: 2_100_000, period: .week, entries: entries, now: now, calendar: calendar)
        #expect(status.period == .week)
        #expect(status.spentThisPeriod == 250_000)
        #expect(status.spentToday == 50_000)
        #expect(status.remainingThisPeriod == 1_850_000)
    }

    @Test func weeklyAllowanceSplitsTheRestOfTheWeekEvenly() {
        let status = BudgetCalculator.status(budget: 2_100_000, period: .week, entries: [], now: weekStart.addingTimeInterval(3_600), calendar: calendar)
        #expect(status.daysLeft == 7)
        #expect(status.daysElapsed == 1)
        #expect(status.allowanceToday == 300_000)
        // Cuối tuần: ngày cuối còn đủ tiền chưa tiêu của cả tuần.
        let lastDay = calendar.date(byAdding: .day, value: 6, to: weekStart)!.addingTimeInterval(3_600)
        let end = BudgetCalculator.status(budget: 2_100_000, period: .week, entries: [], now: lastDay, calendar: calendar)
        #expect(end.daysLeft == 1)
        #expect(end.daysElapsed == 7)
        #expect(end.allowanceToday == 2_100_000)
        #expect(end.allowanceTomorrow == nil)
    }

    @Test func weeklyForecastUsesDaysElapsedInTheWeek() {
        // Thứ Sáu: đã qua một số ngày của tuần; tiêu 600k thì nhịp = 600k / số ngày đã qua.
        let status = BudgetCalculator.status(
            budget: 2_100_000, period: .week, entries: [entry(600_000, weekStart.addingTimeInterval(3_600))], now: now, calendar: calendar
        )
        let forecast = BudgetCalculator.forecast(for: status)
        #expect(forecast.pacePerDay == 600_000 / status.daysElapsed)
        #expect(forecast.projectedLeftover == status.remainingThisPeriod - forecast.pacePerDay * (status.daysLeft - 1))
    }

    @Test func monthlyStatusIsUnchangedByThePeriodParameter() {
        let entries = [entry(1_800_000, TestClock.date(2026, 10, 3))]
        let plain = BudgetCalculator.status(budget: 9_000_000, entries: entries, now: now, calendar: calendar)
        let explicit = BudgetCalculator.status(.monthly(9_000_000), entries: entries, now: now, calendar: calendar)
        #expect(plain == explicit)
        #expect(plain.period == .month)
        #expect(plain.daysElapsed == 9)
    }

    @Test func categoryLimitsAreIgnoredWhenBudgetingByWeek() {
        let entries = [BudgetEntry(amount: 100_000, date: now, categoryKey: "food")]
        let withLimits = BudgetCalculator.status(
            budget: 2_100_000, period: .week, entries: entries, categoryLimits: ["food": 500_000], now: now, calendar: calendar
        )
        let without = BudgetCalculator.status(budget: 2_100_000, period: .week, entries: entries, now: now, calendar: calendar)
        #expect(withLimits == without)
    }

    @Test func dailyAverageFollowsThePeriod() {
        #expect(BudgetCalculator.dailyAverage(budget: 2_100_000, period: .week, now: now, calendar: calendar) == 300_000)
        #expect(BudgetCalculator.dailyAverage(budget: 9_300_000, now: now, calendar: calendar) == 300_000)
    }

    @Test func settingConversions() {
        #expect(BudgetSetting.suggestedWeekly(fromMonthly: 9_000_000) == 2_100_000)
        #expect(BudgetSetting.suggestedWeekly(fromMonthly: 8_000_000) == 1_866_000)
        #expect(BudgetSetting.monthly(9_000_000).monthlyEquivalent(now: now, calendar: calendar) == 9_000_000)
        // Tuần 2,1tr trong tháng 31 ngày: 2,1tr × 31 / 7 = 9,3tr.
        #expect(BudgetSetting(period: .week, amount: 2_100_000).monthlyEquivalent(now: now, calendar: calendar) == 9_300_000)
    }
}

@MainActor
struct WeeklyBudgetSettingsTests {
    private func suite() -> UserDefaults {
        let name = "WeeklyBudgetSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func switchingToWeekSuggestsAnAmountOnce() {
        let defaults = suite()
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        settings.monthlyBudget = 9_000_000
        #expect(settings.budgetSetting == .monthly(9_000_000))
        settings.setBudgetPeriod(.week)
        #expect(settings.weeklyBudget == 2_100_000)
        #expect(settings.budgetSetting == BudgetSetting(period: .week, amount: 2_100_000))
        settings.setActiveBudget(1_500_000)
        #expect(settings.weeklyBudget == 1_500_000 && settings.monthlyBudget == 9_000_000)
        settings.setBudgetPeriod(.month)
        settings.setBudgetPeriod(.week)
        #expect(settings.weeklyBudget == 1_500_000)             // không gợi ý lại, giữ số người dùng đã đặt
        settings.setBudgetPeriod(.month)
        settings.setActiveBudget(10_000_000)
        #expect(settings.monthlyBudget == 10_000_000)
    }

    @Test func periodAndWeeklyAmountSurviveARelaunchAndReachIntents() {
        let defaults = suite()
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        settings.monthlyBudget = 9_000_000
        settings.setBudgetPeriod(.week)
        settings.setActiveBudget(2_000_000)
        let next = AppSettings(defaults: defaults, standardDefaults: defaults)
        #expect(next.budgetPeriod == .week && next.weeklyBudget == 2_000_000)
        #expect(BudgetSetting.load(from: defaults) == BudgetSetting(period: .week, amount: 2_000_000))
    }

    @Test func intentsFallBackToASuggestedWeeklyAmount() {
        let defaults = suite()
        defaults.set(9_000_000, forKey: SettingsKey.monthlyBudget)
        defaults.set(BudgetPeriod.week.rawValue, forKey: SettingsKey.budgetPeriod)
        #expect(BudgetSetting.load(from: defaults) == BudgetSetting(period: .week, amount: 2_100_000))
    }

    @Test func categoryLimitsDoNotShapeTheDailyLimitInWeekMode() {
        let defaults = suite()
        let settings = AppSettings(defaults: defaults, standardDefaults: defaults)
        settings.limitsShapeDaily = true
        let limits = [CategoryBudget(categoryKey: "food", amount: 1_000_000)]
        #expect(settings.dailyLimits(limits) == ["food": 1_000_000])
        settings.monthlyBudget = 9_000_000
        settings.setBudgetPeriod(.week)
        #expect(settings.dailyLimits(limits).isEmpty)
    }
}
