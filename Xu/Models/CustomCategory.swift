import Foundation
import SwiftData

/// Danh mục người dùng tự thêm. `Expense.categoryKey` và `CategoryRule.categoryKey` trỏ tới `key`.
@Model final class CustomCategory {
    var key: String = ""                  // "custom-<uuid>", không đổi khi đổi tên
    var name: String = ""
    var createdAt: Date = Date()

    init(name: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.key = CategoryNaming.makeKey(id: id)
        self.name = name
        self.createdAt = createdAt
    }
}
