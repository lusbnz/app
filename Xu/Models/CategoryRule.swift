import Foundation
import SwiftData

/// App học từ lần người dùng sửa danh mục.
@Model final class CategoryRule {
    var keyword: String = ""              // đã chuẩn hóa bằng TextNormalizer.keyword
    var categoryKey: String = "other"
    var updatedAt: Date = Date()

    init(keyword: String, categoryKey: String, updatedAt: Date = Date()) {
        self.keyword = keyword
        self.categoryKey = categoryKey
        self.updatedAt = updatedAt
    }
}

extension [CategoryRule] {
    /// Bảng tra cho bộ tách. Khi trùng khóa (đồng bộ iCloud có thể tạo bản lặp), luật mới hơn thắng.
    var lookup: [String: String] {
        var table: [String: String] = [:]
        for rule in sorted(by: { $0.updatedAt < $1.updatedAt }) {
            table[rule.keyword] = rule.categoryKey
        }
        return table
    }
}
