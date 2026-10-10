import Foundation
import SwiftData
import Testing
@testable import Xu

/// Cảnh báo tăng giá khi vừa ghi một khoản đăng ký, đọc lịch sử từ SwiftData.
@MainActor
struct SubscriptionWarningTests {
    private let calendar = TestClock.calendar

    /// Ba tháng Netflix 260k, rồi lần ghi mới ngày 5/10. Trả về bộ ghi và lô của lần ghi mới.
    private func makeHistory(newAmount: Int, in container: ModelContainer) throws -> (ExpenseRecorder, UUID, [RecordItem]) {
        let context = container.mainContext
        for month in 7...9 {
            context.insert(Expense(name: "Netflix", amount: 260_000, categoryKey: "fun", date: TestClock.date(2026, month, 5, 9)))
        }
        let date = TestClock.date(2026, 10, 5, 9)
        let added = Expense(name: "netflix", amount: newAmount, categoryKey: "fun", date: date)
        context.insert(added)
        try context.save()
        let items: [RecordItem] = [.expense(ExpenseDraft(name: "netflix", amount: newAmount, categoryKey: "fun", date: date))]
        return (ExpenseRecorder(context: context), added.batchID, items)
    }

    @Test func aHigherChargeOnTheCycleWarnsProUsers() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let (recorder, batchID, items) = try makeHistory(newAmount: 290_000, in: container)
        let warning = recorder.subscriptionWarning(
            for: items, batchID: batchID, defaultDate: TestClock.now, now: TestClock.now, calendar: calendar, isPro: true
        )
        #expect(warning == "Netflix tăng từ 260k lên 290k")
    }

    @Test func freeUsersGetNoSubscriptionWarning() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let (recorder, batchID, items) = try makeHistory(newAmount: 290_000, in: container)
        #expect(recorder.subscriptionWarning(
            for: items, batchID: batchID, defaultDate: TestClock.now, now: TestClock.now, calendar: calendar, isPro: false
        ) == nil)
    }

    @Test func theSamePriceIsQuiet() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let (recorder, batchID, items) = try makeHistory(newAmount: 260_000, in: container)
        #expect(recorder.subscriptionWarning(
            for: items, batchID: batchID, defaultDate: TestClock.now, now: TestClock.now, calendar: calendar, isPro: true
        ) == nil)
    }

    @Test func aLoanOrAnUnrelatedExpenseIsQuiet() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let (recorder, batchID, _) = try makeHistory(newAmount: 290_000, in: container)
        let items: [RecordItem] = [
            .loan(person: "Minh", amount: 200_000),
            .expense(ExpenseDraft(name: "phở", amount: 45_000, categoryKey: "food")),
        ]
        #expect(recorder.subscriptionWarning(
            for: items, batchID: batchID, defaultDate: TestClock.now, now: TestClock.now, calendar: calendar, isPro: true
        ) == nil)
    }
}
