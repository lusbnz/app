import Foundation
import SwiftData

/// Mục tiêu tiết kiệm ("Du lịch Đà Lạt", 10 triệu). Tiền để dành không phải chi tiêu nên không tính vào ngân sách.
@Model final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var targetAmount: Int = 0
    var createdAt: Date = Date()
    /// Ngày muốn đạt mục tiêu; nil là không đặt hạn.
    var deadline: Date?

    init(name: String, targetAmount: Int, deadline: Date? = nil, createdAt: Date = Date()) {
        self.name = name
        self.targetAmount = targetAmount
        self.deadline = deadline
        self.createdAt = createdAt
    }
}

/// Một lần gửi tiền vào (số dương) hoặc rút ra (số âm) của một mục tiêu. Nối với mục tiêu bằng `goalID`,
/// không dùng quan hệ SwiftData, cho đơn giản và tương thích CloudKit.
@Model final class SavingsDeposit {
    var id: UUID = UUID()
    var goalID: UUID = UUID()
    var amount: Int = 0
    var date: Date = Date()
    var note: String = ""

    init(goalID: UUID, amount: Int, date: Date = Date(), note: String = "") {
        self.goalID = goalID
        self.amount = amount
        self.date = date
        self.note = note
    }
}
