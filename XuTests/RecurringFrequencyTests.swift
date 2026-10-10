import Foundation
import SwiftData
import Testing
@testable import Xu

struct RecurringFrequencyTests {
    private let calendar = TestClock.calendar

    private func item(
        _ frequency: RecurringFrequency, day: Int = 1, weekday: Int = 2, month: Int = 1,
        created: Date = TestClock.date(2026, 1, 1), handled: String = "", auto: Bool = false
    ) -> RecurringItem {
        RecurringItem(
            id: UUID(), name: "x", amount: 100_000, categoryKey: "bills", dayOfMonth: day, isOutsideBudget: false,
            createdAt: created, handledMonth: handled, frequency: frequency, weekday: weekday, monthOfYear: month, autoRecord: auto
        )
    }

    @Test func periodKeysDifferByFrequency() {
        let date = TestClock.date(2026, 10, 9)
        #expect(RecurringPlanner.periodKey(date, frequency: .monthly, calendar: calendar) == "2026-10")
        #expect(RecurringPlanner.periodKey(date, frequency: .yearly, calendar: calendar) == "2026")
        let week = RecurringPlanner.periodKey(date, frequency: .weekly, calendar: calendar)
        #expect(week.hasPrefix("2026-W"))
        #expect(RecurringPlanner.periodKey(TestClock.date(2026, 10, 10), frequency: .weekly, calendar: calendar) != "")
    }

    @Test func weeklyIsDueOnTheChosenWeekday() {
        // 9/10/2026 là thứ Sáu (weekday 6).
        let friday = item(.weekly, weekday: 6)
        #expect(RecurringPlanner.isDue(friday, now: TestClock.date(2026, 10, 9, 8), calendar: calendar))
        let saturday = item(.weekly, weekday: 7)
        #expect(!RecurringPlanner.isDue(saturday, now: TestClock.date(2026, 10, 9, 8), calendar: calendar))
        #expect(RecurringPlanner.isDue(saturday, now: TestClock.date(2026, 10, 10, 8), calendar: calendar))
    }

    @Test func weeklyHandledStaysQuietUntilNextWeek() {
        let key = RecurringPlanner.periodKey(TestClock.date(2026, 10, 9), frequency: .weekly, calendar: calendar)
        let friday = item(.weekly, weekday: 6, handled: key)
        #expect(!RecurringPlanner.isDue(friday, now: TestClock.date(2026, 10, 10), calendar: calendar))
        #expect(RecurringPlanner.isDue(friday, now: TestClock.date(2026, 10, 16, 8), calendar: calendar))
    }

    @Test func weeklyFiresOncePerWeekAtNine() {
        let friday = item(.weekly, weekday: 6)
        let fires = RecurringPlanner.fireDates(for: [friday], now: TestClock.date(2026, 10, 9, 10), calendar: calendar)
        #expect(fires.count == 2)                               // thứ Sáu này đã qua 9:00, còn hai tuần tới
        #expect(fires.allSatisfy { calendar.component(.weekday, from: $0.date) == 6 && calendar.component(.hour, from: $0.date) == 9 })
        #expect(Set(fires.map { RecurringPlanner.dayKey($0.date, calendar: calendar) }).count == 2)
    }

    @Test func yearlyDueOnItsMonthAndDay() {
        let birthday = item(.yearly, day: 15, month: 3)
        #expect(!RecurringPlanner.isDue(birthday, now: TestClock.date(2026, 3, 14), calendar: calendar))
        #expect(RecurringPlanner.isDue(birthday, now: TestClock.date(2026, 3, 15), calendar: calendar))
        #expect(RecurringPlanner.isDue(birthday, now: TestClock.date(2026, 9, 1), calendar: calendar))
        let handled = item(.yearly, day: 15, month: 3, handled: "2026")
        #expect(!RecurringPlanner.isDue(handled, now: TestClock.date(2026, 9, 1), calendar: calendar))
        #expect(RecurringPlanner.isDue(handled, now: TestClock.date(2027, 3, 16), calendar: calendar))
    }

    @Test func yearlyFebruary29ClampsInCommonYears() throws {
        let leap = item(.yearly, day: 29, month: 2)
        let due = try #require(RecurringPlanner.dueDate(for: leap, inPeriodOf: TestClock.date(2026, 6, 1), calendar: calendar))
        #expect(calendar.component(.month, from: due) == 2)
        #expect(calendar.component(.day, from: due) == 28)
    }

    @Test func createdAfterThisPeriodsDueDateWaits() {
        let birthday = item(.yearly, day: 15, month: 3, created: TestClock.date(2026, 5, 1))
        #expect(!RecurringPlanner.isDue(birthday, now: TestClock.date(2026, 9, 1), calendar: calendar))
        #expect(RecurringPlanner.isDue(birthday, now: TestClock.date(2027, 3, 15), calendar: calendar))
    }

}

@MainActor
struct RecurringAutoRecordTests {
    private let calendar = TestClock.calendar

    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    @Test func automaticRecordingWritesDueAutoItemsOnly() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        SaveGate.quota = SaveQuota(day: "", count: 0)
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let created = TestClock.date(2026, 9, 1)
        recorder.addRecurring(name: "netflix", amount: 260_000, categoryKey: "fun", dayOfMonth: 3, isOutsideBudget: false, now: created, autoRecord: true)
        recorder.addRecurring(name: "tiền nhà", amount: 3_000_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true, now: created)
        recorder.addRecurring(name: "bảo hiểm", amount: 5_000_000, categoryKey: "bills", dayOfMonth: 25, isOutsideBudget: true, now: created, autoRecord: true)

        let batches = recorder.recordAutomaticRecurring(now: TestClock.now, calendar: calendar)
        #expect(batches.count == 1)
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.map(\.name) == ["netflix"])               // nhà không bật tự ghi, bảo hiểm chưa đến hạn
        #expect(recorder.recordAutomaticRecurring(now: TestClock.now, calendar: calendar).isEmpty)   // không ghi hai lần
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 1)
    }

    @Test func automaticRecordingStopsAtFreeDailyLimit() throws {
        let quota = SaveGate.quota
        let wasPro = SaveGate.isPro
        defer { SaveGate.quota = quota }
        guard !wasPro else { return }
        SaveGate.quota = SaveQuota(day: SaveQuota.dayKey(TestClock.now, calendar: calendar), count: SaveQuota.freeDailyLimit)
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        recorder.addRecurring(name: "netflix", amount: 260_000, categoryKey: "fun", dayOfMonth: 3, isOutsideBudget: false, now: TestClock.date(2026, 9, 1), autoRecord: true)
        #expect(recorder.recordAutomaticRecurring(now: TestClock.now, calendar: calendar).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    @Test func changingFrequencyResetsHandledPeriod() {
        let (recorder, _, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let plan = recorder.addRecurring(name: "x", amount: 1_000, categoryKey: "other", dayOfMonth: 5, isOutsideBudget: false, now: TestClock.date(2026, 9, 1))
        recorder.skipRecurring(plan, now: TestClock.now, calendar: calendar)
        #expect(plan.handledMonth == "2026-10")
        recorder.updateRecurring(plan, name: "x", amount: 1_000, categoryKey: "other", dayOfMonth: 5, isOutsideBudget: false, frequency: .weekly, weekday: 6)
        #expect(plan.handledMonth == "")
        #expect(plan.frequency == .weekly)
    }
}
