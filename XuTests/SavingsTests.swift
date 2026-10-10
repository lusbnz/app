import Foundation
import SwiftData
import Testing
@testable import Xu

struct SavingsPlannerTests {
    private let calendar = TestClock.calendar
    private let now = TestClock.now                      // 9/10/2026

    @Test func progressWithoutDeadline() {
        let progress = SavingsPlanner.progress(target: 10_000_000, saved: 2_500_000, deadline: nil, now: now, calendar: calendar)
        #expect(progress.fraction == 0.25)
        #expect(progress.remaining == 7_500_000)
        #expect(!progress.isDone && !progress.isOverdue)
        #expect(progress.monthsLeft == nil && progress.neededPerMonth == nil)
    }

    @Test func neededPerMonthRoundsUpToAThousand() {
        // Còn 7,5tr, hạn 10/1/2027: 3 tháng đủ và 1 ngày lẻ → tính 4 tháng → 1.875.000.
        let deadline = TestClock.date(2027, 1, 10)
        let progress = SavingsPlanner.progress(target: 10_000_000, saved: 2_500_000, deadline: deadline, now: now, calendar: calendar)
        #expect(progress.monthsLeft == 4)
        #expect(progress.neededPerMonth == 1_875_000)
        // Hạn đúng 3 tháng tròn: 9/1/2027.
        let exact = SavingsPlanner.progress(target: 9_000_000, saved: 0, deadline: TestClock.date(2027, 1, 9), now: now, calendar: calendar)
        #expect(exact.monthsLeft == 3)
        #expect(exact.neededPerMonth == 3_000_000)
        // Làm tròn lên: 10tr / 3 = 3.333.334 → 3.334.000.
        let rounded = SavingsPlanner.progress(target: 10_000_000, saved: 0, deadline: TestClock.date(2027, 1, 9), now: now, calendar: calendar)
        #expect(rounded.neededPerMonth == 3_334_000)
    }

    @Test func deadlineWithinThisMonthNeedsEverythingNow() {
        let progress = SavingsPlanner.progress(target: 1_000_000, saved: 400_000, deadline: TestClock.date(2026, 10, 20), now: now, calendar: calendar)
        #expect(progress.monthsLeft == 1)
        #expect(progress.neededPerMonth == 600_000)
        let today = SavingsPlanner.progress(target: 1_000_000, saved: 400_000, deadline: now, now: now, calendar: calendar)
        #expect(today.monthsLeft == 1 && !today.isOverdue)
    }

    @Test func overdueAndDone() {
        let overdue = SavingsPlanner.progress(target: 1_000_000, saved: 400_000, deadline: TestClock.date(2026, 10, 1), now: now, calendar: calendar)
        #expect(overdue.isOverdue)
        #expect(overdue.monthsLeft == nil && overdue.neededPerMonth == nil)
        let done = SavingsPlanner.progress(target: 1_000_000, saved: 1_200_000, deadline: TestClock.date(2026, 10, 1), now: now, calendar: calendar)
        #expect(done.isDone && !done.isOverdue)
        #expect(done.fraction == 1 && done.remaining == 0 && done.neededPerMonth == nil)
    }

    @Test func negativeSavedNeverShowsNegativeProgress() {
        let progress = SavingsPlanner.progress(target: 1_000_000, saved: -5, deadline: nil, now: now, calendar: calendar)
        #expect(progress.saved == 0 && progress.fraction == 0)
    }

    @Test func nameIsCleanedAndLimited() {
        #expect(SavingsPlanner.cleanName("  Du lịch   Đà Lạt ") == "Du lịch Đà Lạt")
        #expect(SavingsPlanner.cleanName("   ") == nil)
        #expect(SavingsPlanner.cleanName(String(repeating: "a", count: 100))?.count == SavingsPlanner.maxNameLength)
    }
}

@MainActor
struct SavingsRecorderTests {
    private func make() -> (ExpenseRecorder, ModelContext, ModelContainer) {
        let container = XuStore.inMemory()
        return (ExpenseRecorder(context: container.mainContext), container.mainContext, container)
    }

    @Test func addingAndEditingGoals() throws {
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        #expect(recorder.addGoal(name: "  ", target: 1_000_000, deadline: nil) == nil)
        #expect(recorder.addGoal(name: "Xe máy", target: 0, deadline: nil) == nil)
        let goal = try #require(recorder.addGoal(name: " Du  lịch ", target: 10_000_000, deadline: nil))
        #expect(goal.name == "Du lịch")
        #expect(recorder.updateGoal(goal, name: "Đà Lạt", target: 12_000_000, deadline: TestClock.date(2027, 1, 1)))
        #expect(!recorder.updateGoal(goal, name: "", target: 12_000_000, deadline: nil))
        let stored = try #require(try context.fetch(FetchDescriptor<SavingsGoal>()).first)
        #expect(stored.name == "Đà Lạt" && stored.targetAmount == 12_000_000 && stored.deadline != nil)
    }

    @Test func depositsAddUpAndWithdrawalsCannotGoNegative() throws {
        let (recorder, _, container) = make()
        defer { withExtendedLifetime(container) {} }
        let goal = try #require(recorder.addGoal(name: "Xe", target: 10_000_000, deadline: nil))
        #expect(recorder.addDeposit(to: goal, amount: 0) == nil)
        #expect(recorder.addDeposit(to: goal, amount: -100_000) == nil)          // chưa có gì để rút
        recorder.addDeposit(to: goal, amount: 3_000_000)
        recorder.addDeposit(to: goal, amount: 500_000, note: " lì xì ")
        #expect(recorder.saved(for: goal.id) == 3_500_000)
        #expect(recorder.addDeposit(to: goal, amount: -4_000_000) == nil)        // rút quá số đang có
        #expect(recorder.addDeposit(to: goal, amount: -1_000_000) != nil)
        #expect(recorder.saved(for: goal.id) == 2_500_000)
        #expect(recorder.deposits(for: goal.id).contains { $0.note == "lì xì" })
    }

    @Test func goalsKeepTheirOwnMoney() throws {
        let (recorder, _, container) = make()
        defer { withExtendedLifetime(container) {} }
        let first = try #require(recorder.addGoal(name: "A", target: 1_000_000, deadline: nil))
        let second = try #require(recorder.addGoal(name: "B", target: 1_000_000, deadline: nil))
        recorder.addDeposit(to: first, amount: 100_000)
        recorder.addDeposit(to: second, amount: 250_000)
        #expect(recorder.saved(for: first.id) == 100_000)
        #expect(recorder.saved(for: second.id) == 250_000)
    }

    @Test func deletingADepositCannotLeaveNegativeSavings() throws {
        let (recorder, _, container) = make()
        defer { withExtendedLifetime(container) {} }
        let goal = try #require(recorder.addGoal(name: "A", target: 1_000_000, deadline: nil))
        let big = try #require(recorder.addDeposit(to: goal, amount: 500_000, date: Date(timeIntervalSince1970: 1)))
        recorder.addDeposit(to: goal, amount: -400_000, date: Date(timeIntervalSince1970: 2))
        #expect(!recorder.deleteDeposit(big))                    // xóa lần gửi đã bị rút một phần sẽ ra âm
        #expect(recorder.saved(for: goal.id) == 100_000)
        let withdrawal = try #require(recorder.deposits(for: goal.id).first { $0.amount < 0 })
        #expect(recorder.deleteDeposit(withdrawal))
        #expect(recorder.saved(for: goal.id) == 500_000)
    }

    @Test func deletingAGoalDeletesItsDepositsOnly() throws {
        let (recorder, context, container) = make()
        defer { withExtendedLifetime(container) {} }
        let doomed = try #require(recorder.addGoal(name: "A", target: 1_000_000, deadline: nil))
        let kept = try #require(recorder.addGoal(name: "B", target: 1_000_000, deadline: nil))
        recorder.addDeposit(to: doomed, amount: 100_000)
        recorder.addDeposit(to: kept, amount: 200_000)
        recorder.deleteGoal(doomed)
        #expect(try context.fetch(FetchDescriptor<SavingsGoal>()).map(\.name) == ["B"])
        #expect(try context.fetch(FetchDescriptor<SavingsDeposit>()).map(\.amount) == [200_000])
    }
}
