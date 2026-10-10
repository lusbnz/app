import Foundation
import SwiftData

/// Mục tiêu tiết kiệm và các lần gửi, rút.
extension ExpenseRecorder {
    @discardableResult
    func addGoal(name: String, target: Int, deadline: Date?) -> SavingsGoal? {
        guard let name = SavingsPlanner.cleanName(name), target > 0 else { return nil }
        let goal = SavingsGoal(name: name, targetAmount: target, deadline: deadline)
        context.insert(goal)
        commit()
        return goal
    }

    @discardableResult
    func updateGoal(_ goal: SavingsGoal, name: String, target: Int, deadline: Date?) -> Bool {
        guard let name = SavingsPlanner.cleanName(name), target > 0 else { return false }
        goal.name = name
        goal.targetAmount = target
        goal.deadline = deadline
        commit()
        return true
    }

    /// Xóa mục tiêu cùng mọi lần gửi, rút của nó.
    func deleteGoal(_ goal: SavingsGoal) {
        let id = goal.id
        for deposit in deposits(for: id) { context.delete(deposit) }
        context.delete(goal)
        commit()
    }

    func deposits(for goalID: UUID) -> [SavingsDeposit] {
        (try? context.fetch(FetchDescriptor<SavingsDeposit>(
            predicate: #Predicate { $0.goalID == goalID }, sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
    }

    func saved(for goalID: UUID) -> Int {
        max(0, deposits(for: goalID).reduce(0) { $0 + $1.amount })
    }

    /// Gửi thêm (số dương) hoặc rút bớt (số âm). Không cho rút quá số đang có. Nil khi không hợp lệ.
    @discardableResult
    func addDeposit(to goal: SavingsGoal, amount: Int, date: Date = Date(), note: String = "") -> SavingsDeposit? {
        guard amount != 0, saved(for: goal.id) + amount >= 0 else { return nil }
        let deposit = SavingsDeposit(
            goalID: goal.id, amount: amount, date: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(deposit)
        commit()
        return deposit
    }

    /// Xóa một lần gửi hoặc rút. Không cho xóa nếu số đang có sẽ âm (xóa một lần gửi mà đã rút phần đó rồi).
    @discardableResult
    func deleteDeposit(_ deposit: SavingsDeposit) -> Bool {
        let remaining = saved(for: deposit.goalID) - deposit.amount
        let onlyDeposit = deposits(for: deposit.goalID).count == 1
        guard remaining >= 0 || onlyDeposit else { return false }
        context.delete(deposit)
        commit()
        return true
    }
}
