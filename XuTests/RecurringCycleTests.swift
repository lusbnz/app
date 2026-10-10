import Foundation
import SwiftData
import Testing
@testable import Xu

/// Chu kỳ hai tuần, mỗi quý và lời nhắc trước một ngày của khoản định kỳ.
/// 9/10/2026 là thứ Sáu; thứ Hai kế tiếp là 12/10.
struct RecurringCycleTests {
    private let calendar = TestClock.calendar

    private func item(
        _ frequency: RecurringFrequency, day: Int = 5, weekday: Int = 2, month: Int = 1,
        created: Date = TestClock.date(2026, 1, 1), handled: String = "", remind: Bool = false
    ) -> RecurringItem {
        RecurringItem(
            id: UUID(), name: "x", amount: 100_000, categoryKey: "bills", dayOfMonth: day, isOutsideBudget: false,
            createdAt: created, handledMonth: handled, frequency: frequency, weekday: weekday, monthOfYear: month,
            remindDayBefore: remind
        )
    }

    // MARK: - Hai tuần một lần

    @Test func biweeklyStartsOnTheFirstChosenWeekdayAfterCreation() {
        let created = TestClock.date(2026, 10, 9)                            // thứ Sáu
        let plan = item(.biweekly, weekday: 2, created: created)
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 11), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 12, 8), calendar: calendar))
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 19, 8), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 26, 8), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 11, 9, 8), calendar: calendar))
    }

    @Test func biweeklyCreatedOnTheChosenWeekdayIsDueToday() {
        let plan = item(.biweekly, weekday: 2, created: TestClock.date(2026, 10, 12, 8))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 12, 10), calendar: calendar))
        #expect(RecurringPlanner.nextDueDate(for: plan, now: TestClock.date(2026, 10, 13), calendar: calendar)
                == TestClock.date(2026, 10, 26, 0))
    }

    @Test func biweeklyHasNoDueDateInTheOffWeek() throws {
        let plan = item(.biweekly, weekday: 2, created: TestClock.date(2026, 10, 9))
        #expect(RecurringPlanner.dueDate(for: plan, inPeriodOf: TestClock.date(2026, 10, 21), calendar: calendar) == nil)
        let due = try #require(RecurringPlanner.dueDate(for: plan, inPeriodOf: TestClock.date(2026, 10, 28), calendar: calendar))
        #expect(calendar.component(.day, from: due) == 26)
    }

    @Test func biweeklyHandledStaysQuietThroughTheNextCycleWeek() {
        let key = RecurringPlanner.periodKey(TestClock.date(2026, 10, 12), frequency: .biweekly, calendar: calendar)
        let plan = item(.biweekly, weekday: 2, created: TestClock.date(2026, 10, 9), handled: key)
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 14), calendar: calendar))
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 20), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 26, 8), calendar: calendar))
    }

    @Test func biweeklyFiresEveryOtherWeekAtNine() {
        let plan = item(.biweekly, weekday: 2, created: TestClock.date(2026, 10, 9))
        let fires = RecurringPlanner.fireDates(for: [plan], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.map(\.date) == [TestClock.date(2026, 10, 12, 9), TestClock.date(2026, 10, 26, 9)])
        #expect(fires.allSatisfy { !$0.isDayBefore })
    }

    @Test func biweeklyExpenseDateIsTheDueDayWhenLate() {
        let plan = item(.biweekly, weekday: 2, created: TestClock.date(2026, 10, 9))
        let date = RecurringPlanner.expenseDate(for: plan, now: TestClock.date(2026, 10, 14, 9), calendar: calendar)
        #expect(date == TestClock.date(2026, 10, 12, 12))
    }

    // MARK: - Mỗi quý

    @Test func quarterMonthsAreTheThreeMonthStepsFromTheStart() {
        #expect(RecurringPlanner.quarterMonths(startingAt: 1) == [1, 4, 7, 10])
        #expect(RecurringPlanner.quarterMonths(startingAt: 11) == [2, 5, 8, 11])
        #expect(RecurringPlanner.quarterMonths(startingAt: 3) == [3, 6, 9, 12])
        #expect(RecurringPlanner.quarterMonths(startingAt: 0) == [1, 4, 7, 10])
        #expect(RecurringPlanner.quarterMonths(startingAt: 13) == [3, 6, 9, 12])
    }

    @Test func quarterlyIsDueOnlyInItsMonths() {
        let plan = item(.quarterly, day: 5, month: 2)                          // 2, 5, 8, 11
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 20), calendar: calendar))
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 11, 4), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 11, 5), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2026, 11, 28), calendar: calendar))
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 12, 5), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2027, 2, 5), calendar: calendar))
    }

    @Test func quarterlyClampsTheDayInShortMonths() throws {
        let plan = item(.quarterly, day: 31, month: 2)
        let feb = try #require(RecurringPlanner.dueDate(for: plan, inPeriodOf: TestClock.date(2027, 2, 10), calendar: calendar))
        #expect(calendar.component(.day, from: feb) == 28)
        let nov = try #require(RecurringPlanner.dueDate(for: plan, inPeriodOf: TestClock.date(2026, 11, 10), calendar: calendar))
        #expect(calendar.component(.day, from: nov) == 30)
    }

    @Test func quarterlyHandledMonthStaysQuietUntilTheNextCycleMonth() {
        let handled = item(.quarterly, day: 5, month: 2, handled: "2026-11")
        #expect(!RecurringPlanner.isDue(handled, now: TestClock.date(2026, 11, 20), calendar: calendar))
        #expect(!RecurringPlanner.isDue(handled, now: TestClock.date(2026, 12, 20), calendar: calendar))
        #expect(RecurringPlanner.isDue(handled, now: TestClock.date(2027, 2, 6), calendar: calendar))
    }

    @Test func quarterlyCreatedAfterThisMonthsDueDateWaitsThreeMonths() {
        let plan = item(.quarterly, day: 5, month: 1, created: TestClock.date(2026, 10, 7))   // 1, 4, 7, 10
        #expect(!RecurringPlanner.isDue(plan, now: TestClock.date(2026, 10, 9), calendar: calendar))
        #expect(RecurringPlanner.isDue(plan, now: TestClock.date(2027, 1, 5), calendar: calendar))
    }

    @Test func quarterlyFiresOnceInTheLookaheadWindow() {
        let plan = item(.quarterly, day: 5, month: 2)
        let fires = RecurringPlanner.fireDates(for: [plan], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.map(\.date) == [TestClock.date(2026, 11, 5, 9)])
    }

    // MARK: - Ngày đến hạn kế tiếp

    @Test func nextDueDateIsTodayWhenDueTodayAndUnhandled() {
        let plan = item(.monthly, day: 9)
        #expect(RecurringPlanner.nextDueDate(for: plan, now: TestClock.now, calendar: calendar) == TestClock.date(2026, 10, 9, 0))
    }

    @Test func nextDueDateSkipsHandledAndPastPeriods() {
        let handled = item(.monthly, day: 20, handled: "2026-10")
        #expect(RecurringPlanner.nextDueDate(for: handled, now: TestClock.now, calendar: calendar) == TestClock.date(2026, 11, 20, 0))
        let passed = item(.monthly, day: 5)
        #expect(RecurringPlanner.nextDueDate(for: passed, now: TestClock.now, calendar: calendar) == TestClock.date(2026, 11, 5, 0))
    }

    @Test func nextDueDateForQuarterlyJumpsToTheNextCycleMonth() {
        let plan = item(.quarterly, day: 5, month: 1)                          // 1, 4, 7, 10
        #expect(RecurringPlanner.nextDueDate(for: plan, now: TestClock.now, calendar: calendar) == TestClock.date(2027, 1, 5, 0))
    }

    @Test func nextDueDateNeverPrecedesCreation() {
        // Ngày tạo ở tương lai (đồng hồ máy bị chỉnh): ngày 15 tháng này nằm trước ngày tạo nên không tính.
        let plan = item(.monthly, day: 15, created: TestClock.date(2026, 10, 20))
        #expect(RecurringPlanner.nextDueDate(for: plan, now: TestClock.now, calendar: calendar) == TestClock.date(2026, 11, 15, 0))
    }

    // MARK: - Nhắc trước một ngày

    @Test func dayBeforeAddsAReminderAtNineTheDayBefore() {
        let rent = item(.monthly, day: 15, remind: true)
        let fires = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.map(\.date) == [
            TestClock.date(2026, 10, 14, 9), TestClock.date(2026, 10, 15, 9),
            TestClock.date(2026, 11, 14, 9), TestClock.date(2026, 11, 15, 9),
        ])
        #expect(fires.map(\.isDayBefore) == [true, false, true, false])
    }

    @Test func withoutDayBeforeThereIsOnlyTheDueDayReminder() {
        let rent = item(.monthly, day: 15)
        let fires = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.count == 2)
        #expect(fires.allSatisfy { !$0.isDayBefore })
    }

    @Test func dayBeforeForTheFirstOfTheMonthLandsInThePreviousMonth() {
        let rent = item(.monthly, day: 1, remind: true)
        let fires = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.map(\.date).first == TestClock.date(2026, 10, 31, 9))
        #expect(fires.first?.isDayBefore == true)
        #expect(fires.dropFirst().first?.date == TestClock.date(2026, 11, 1, 9))
    }

    @Test func passedDayBeforeIsSkippedButTheDueDayStays() {
        let rent = item(.monthly, day: 15, remind: true)
        let fires = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 14, 10), calendar: calendar)
        #expect(fires.first?.date == TestClock.date(2026, 10, 15, 9))
        #expect(fires.first?.isDayBefore == false)
    }

    @Test func handledPeriodHasNoDayBeforeReminderEither() {
        let rent = item(.monthly, day: 15, handled: "2026-10", remind: true)
        let fires = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.map(\.date) == [TestClock.date(2026, 11, 14, 9), TestClock.date(2026, 11, 15, 9)])
    }

    // MARK: - Chữ hiển thị và lưu

    @MainActor
    @Test func quarterlyScheduleTextNamesItsMonths() {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let plan = ExpenseRecorder(context: container.mainContext).addRecurring(
            name: "bảo hiểm", amount: 1_500_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: false,
            now: TestClock.now, frequency: .quarterly, monthOfYear: 11
        )
        #expect(plan.scheduleText(calendar: calendar) == "ngày 5 các tháng 2, 5, 8, 11")
    }

    @MainActor
    @Test func recorderStoresTheNewCycleAndTheReminderFlag() {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        let plan = recorder.addRecurring(
            name: "dọn nhà", amount: 400_000, categoryKey: "bills", dayOfMonth: 1, isOutsideBudget: false,
            now: TestClock.now, frequency: .biweekly, weekday: 7, remindDayBefore: true
        )
        #expect(plan.frequency == .biweekly)
        #expect(plan.remindDayBefore)
        #expect(plan.item.remindDayBefore && plan.item.frequency == .biweekly)
        recorder.updateRecurring(
            plan, name: "dọn nhà", amount: 400_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: false,
            frequency: .quarterly, monthOfYear: 2, remindDayBefore: false
        )
        #expect(plan.frequency == .quarterly)
        #expect(plan.monthOfYear == 2)
        #expect(!plan.remindDayBefore)
    }

    @MainActor
    @Test func recordingAQuarterlyPlanMarksItsMonthHandled() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        SaveGate.quota = SaveQuota(day: "", count: 0)
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        let plan = recorder.addRecurring(
            name: "bảo hiểm", amount: 1_500_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: false,
            now: TestClock.date(2026, 1, 1), frequency: .quarterly, monthOfYear: 2
        )
        let now = TestClock.date(2026, 11, 6)
        #expect(recorder.recordRecurring(plan, now: now, calendar: calendar) != nil)
        #expect(plan.handledMonth == "2026-11")
        #expect(recorder.recordRecurring(plan, now: now, calendar: calendar) == nil)
        #expect(try container.mainContext.fetch(FetchDescriptor<Expense>()).count == 1)
    }
}
