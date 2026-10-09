import Foundation
import SwiftData

/// "ứng cho Minh 200k". Không phải chi tiêu, không bao giờ tính vào ngân sách.
@Model final class Loan {
    var id: UUID = UUID()
    var person: String = ""
    var amount: Int = 0
    var date: Date = Date()
    var isRepaid: Bool = false

    init(person: String, amount: Int, date: Date = Date()) {
        self.person = person
        self.amount = amount
        self.date = date
    }
}
