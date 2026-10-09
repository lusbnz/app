import Foundation
import SwiftData
import Testing
@testable import Xu

struct RecurringPlannerTests {
    private let calendar = TestClock.calendar

    private func item(day: Int, created: Date = TestClock.date(2026, 1, 1), handled: String = "") -> RecurringItem {
        RecurringItem(
            id: UUID(), name: "tiền nhà", amount: 3_000_000, categoryKey: "bills", dayOfMonth: day,
            isOutsideBudget: true, createdAt: created, handledMonth: handled
        )
    }

    @Test func monthKeyIsPaddedAndStable() {
        #expect(RecurringPlanner.monthKey(TestClock.date(2026, 3, 9), calendar: calendar) == "2026-03")
        #expect(RecurringPlanner.monthKey(TestClock.date(2026, 10, 9), calendar: calendar) == "2026-10")
    }

    @Test func dueDateClampsToLastDayOfShortMonths() throws {
        let feb = try #require(RecurringPlanner.dueDate(day: 31, inMonthOf: TestClock.date(2026, 2, 10), calendar: calendar))
        #expect(calendar.component(.day, from: feb) == 28)
        let apr = try #require(RecurringPlanner.dueDate(day: 31, inMonthOf: TestClock.date(2026, 4, 10), calendar: calendar))
        #expect(calendar.component(.day, from: apr) == 30)
        let oct = try #require(RecurringPlanner.dueDate(day: 31, inMonthOf: TestClock.date(2026, 10, 10), calendar: calendar))
        #expect(calendar.component(.day, from: oct) == 31)
    }

    @Test func dueOnAndAfterTheDayButNotBefore() {
        let rent = item(day: 9)
        #expect(!RecurringPlanner.isDue(rent, now: TestClock.date(2026, 10, 8, 23), calendar: calendar))
        #expect(RecurringPlanner.isDue(rent, now: TestClock.date(2026, 10, 9, 0), calendar: calendar))
        #expect(RecurringPlanner.isDue(rent, now: TestClock.date(2026, 10, 25), calendar: calendar))
    }

    @Test func handledMonthIsNotDueAgainUntilNextMonth() {
        let rent = item(day: 5, handled: "2026-10")
        #expect(!RecurringPlanner.isDue(rent, now: TestClock.now, calendar: calendar))
        #expect(RecurringPlanner.isDue(rent, now: TestClock.date(2026, 11, 6), calendar: calendar))
    }

    @Test func createdAfterThisMonthsDueDateWaitsForNextMonth() {
        let rent = item(day: 5, created: TestClock.date(2026, 10, 7))
        #expect(!RecurringPlanner.isDue(rent, now: TestClock.date(2026, 10, 9), calendar: calendar))
        #expect(RecurringPlanner.isDue(rent, now: TestClock.date(2026, 11, 5), calendar: calendar))
    }

    @Test func createdOnTheDueDayIsDueImmediately() {
        let rent = item(day: 9, created: TestClock.date(2026, 10, 9, 10))
        #expect(RecurringPlanner.isDue(rent, now: TestClock.date(2026, 10, 9, 15), calendar: calendar))
    }

    @Test func expenseDateIsDueDayNoonWhenLateOtherwiseNow() {
        let rent = item(day: 5)
        let late = RecurringPlanner.expenseDate(for: rent, now: TestClock.now, calendar: calendar)
        #expect(late == TestClock.date(2026, 10, 5, 12))
        let today = item(day: 9)
        #expect(RecurringPlanner.expenseDate(for: today, now: TestClock.now, calendar: calendar) == TestClock.now)
    }

    @Test func fireDatesCoverThisAndNextMonthAtNine() {
        let rent = item(day: 20)
        let dates = RecurringPlanner.fireDates(for: [rent], now: TestClock.now, calendar: calendar)
        #expect(dates.map(\.date) == [TestClock.date(2026, 10, 20, 9), TestClock.date(2026, 11, 20, 9)])
    }

    @Test func fireDatesSkipPastHandledAndSortAcrossItems() {
        let past = item(day: 5)
        let handled = item(day: 20, handled: "2026-10")
        let later = item(day: 25)
        let dates = RecurringPlanner.fireDates(for: [past, handled, later], now: TestClock.now, calendar: calendar)
        // Ngày 5 tháng 10 đã qua, ngày 20 tháng 10 đã xử lý nên chỉ còn tháng 11.
        #expect(dates.map(\.id) == [later.id, past.id, handled.id, later.id])
        #expect(dates.first?.date == TestClock.date(2026, 10, 25, 9))
    }

    @Test func fireDatesIgnoreOccurrencesBeforeCreation() {
        let rent = item(day: 5, created: TestClock.date(2026, 10, 7))
        let dates = RecurringPlanner.fireDates(for: [rent], now: TestClock.date(2026, 10, 8), calendar: calendar)
        #expect(dates.map(\.date) == [TestClock.date(2026, 11, 5, 9)])
    }
}

@MainActor
struct RecurringRecorderTests {
    private func makeRecorder() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    @Test func recordingCreatesExpenseOnceAndMarksMonthHandled() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let calendar = TestClock.calendar
        let rent = recorder.addRecurring(
            name: "tiền nhà", amount: 3_000_000, categoryKey: "bills", dayOfMonth: 5, isOutsideBudget: true,
            now: TestClock.date(2026, 9, 1)
        )

        let batch = try #require(recorder.recordRecurring(rent, now: TestClock.now, calendar: calendar))
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.count == 1)
        let expense = try #require(all.first)
        #expect(expense.batchID == batch.batchID)
        #expect(expense.name == "tiền nhà")
        #expect(expense.amount == 3_000_000)
        #expect(expense.isOutsideBudget)
        #expect(expense.date == TestClock.date(2026, 10, 5, 12))
        #expect(rent.handledMonth == "2026-10")

        #expect(recorder.recordRecurring(rent, now: TestClock.now, calendar: calendar) == nil)
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 1)
    }

    @Test func skippingRecordsNothingAndSilencesThisMonth() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let calendar = TestClock.calendar
        let netflix = recorder.addRecurring(
            name: "netflix", amount: 260_000, categoryKey: "fun", dayOfMonth: 3, isOutsideBudget: false,
            now: TestClock.date(2026, 9, 1)
        )
        #expect(RecurringPlanner.isDue(netflix.item, now: TestClock.now, calendar: calendar))
        recorder.skipRecurring(netflix, now: TestClock.now, calendar: calendar)
        #expect(!RecurringPlanner.isDue(netflix.item, now: TestClock.now, calendar: calendar))
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(RecurringPlanner.isDue(netflix.item, now: TestClock.date(2026, 11, 3), calendar: calendar))
    }

    @Test func updateAndDeleteWork() throws {
        let (recorder, context, container) = makeRecorder()
        defer { withExtendedLifetime(container) {} }
        let item = recorder.addRecurring(
            name: "gym", amount: 500_000, categoryKey: "health", dayOfMonth: 1, isOutsideBudget: false, now: Date()
        )
        recorder.updateRecurring(item, name: "gym vip", amount: 700_000, categoryKey: "health", dayOfMonth: 15, isOutsideBudget: true)
        let found = try #require(recorder.recurring(id: item.id))
        #expect(found.name == "gym vip" && found.amount == 700_000 && found.dayOfMonth == 15 && found.isOutsideBudget)
        recorder.deleteRecurring(found)
        #expect(recorder.recurring(id: item.id) == nil)
        #expect(try context.fetch(FetchDescriptor<RecurringExpense>()).isEmpty)
    }
}
