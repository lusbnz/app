import Foundation
import SwiftData

@Model final class Expense {
    var id: UUID = UUID()
    var name: String = ""                 // giữ nguyên chữ người dùng gõ: "phở"
    var amount: Int = 0                   // phần của người dùng, đơn vị đồng
    var categoryKey: String = "other"
    var date: Date = Date()               // ngày phát sinh, có thể là ngày trên hóa đơn
    var createdAt: Date = Date()
    var rawText: String = ""              // cả dòng gốc đã gõ
    var batchID: UUID = UUID()            // các khoản lưu cùng một lần bấm Ghi, dùng cho Hoàn tác
    var isOutsideBudget: Bool = false     // khoản lớn, không tính vào hạn mức
    var originalAmount: Int?              // 460.000 khi gõ "460k chia 4"
    var splitCount: Int?                  // 4
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    @Attribute(.externalStorage) var photo: Data?   // JPEG đã nén
    var authorName: String?               // để dành cho dùng chung, bản này luôn nil

    init(name: String, amount: Int, categoryKey: String = "other", date: Date = Date()) {
        self.name = name
        self.amount = amount
        self.categoryKey = categoryKey
        self.date = date
        self.createdAt = date
    }
}

extension Expense {
    var displayName: String {
        name.isEmpty ? String(localized: "khoản chi") : name
    }

    /// "460k chia 4" cho khoản chia tiền.
    var splitNote: String? {
        guard let originalAmount, let splitCount else { return nil }
        return String(localized: "\(MoneyFormatter.short(originalAmount)) chia \(splitCount)")
    }

    var budgetEntry: BudgetEntry {
        BudgetEntry(amount: amount, date: date, isOutsideBudget: isOutsideBudget)
    }
}

extension Expense {
    var record: SpendingRecord {
        SpendingRecord(name: name, amount: amount, categoryKey: categoryKey, date: date, isOutsideBudget: isOutsideBudget)
    }
}
