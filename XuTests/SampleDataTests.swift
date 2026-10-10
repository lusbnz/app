import Foundation
import SwiftData
import Testing
@testable import Xu

struct SampleDataTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now

    @Test func isDeterministic() {
        #expect(SampleData.expenses(days: 60, now: now, calendar: calendar) == SampleData.expenses(days: 60, now: now, calendar: calendar))
    }

    @Test func staysInThePastWithinTheRequestedDays() {
        let today = calendar.startOfDay(for: now)
        let oldest = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let items = SampleData.expenses(days: 60, now: now, calendar: calendar)
        #expect(items.count > 100)
        #expect(items.allSatisfy { $0.date < today && $0.date >= oldest })
        #expect(items.allSatisfy { $0.amount >= 5_000 && $0.amount % 1_000 == 0 })
    }

    @Test func someItemsCarryANamedPlaceWithCoordinates() {
        let items = SampleData.expenses(days: 90, now: now, calendar: calendar)
        let located = items.compactMap(\.place)
        #expect(located.count > 20)
        #expect(Set(located.map(\.name)).count >= 4)
        #expect(located.allSatisfy { abs($0.latitude - 10.77) < 0.05 && abs($0.longitude - 106.70) < 0.05 })
    }

    @Test func hasQuietDaysHeavyDaysAndOutsideBudgetItems() {
        let items = SampleData.expenses(days: 90, now: now, calendar: calendar)
        let days = Set(items.map { calendar.startOfDay(for: $0.date) })
        #expect(days.count < 90)                                  // có ngày để trống
        #expect(items.contains { $0.isOutsideBudget })
        let perDay = Dictionary(grouping: items.filter { !$0.isOutsideBudget }) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        #expect(perDay.values.contains { $0 > 400_000 })           // có ngày tiêu nặng
        #expect(perDay.values.contains { $0 < 150_000 })           // có ngày nhẹ
    }
}

@MainActor
struct SampleDataRecorderTests {
    @Test func insertingAndRemovingTouchesOnlySampleExpenses() throws {
        let quota = SaveGate.quota
        defer { SaveGate.quota = quota }
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        recorder.record([.expense(ExpenseDraft(name: "phở", amount: 45_000, categoryKey: "food"))])

        let inserted = recorder.insertSampleData(days: 30, now: TestClock.now, calendar: TestClock.calendar)
        #expect(inserted > 0)
        let all = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(all.count == inserted + 1)
        #expect(all.filter { $0.rawText == SampleData.marker }.count == inserted)

        #expect(recorder.removeSampleData() == inserted)
        let left = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(left.map(\.name) == ["phở"])
    }

    @Test func insertingTwiceDoesNotDuplicate() throws {
        let container = XuStore.inMemory()
        defer { withExtendedLifetime(container) {} }
        let recorder = ExpenseRecorder(context: container.mainContext)
        let first = recorder.insertSampleData(days: 30, now: TestClock.now, calendar: TestClock.calendar)
        _ = recorder.insertSampleData(days: 30, now: TestClock.now, calendar: TestClock.calendar)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Expense>()) == first)
    }
}
