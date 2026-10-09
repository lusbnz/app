import Foundation

/// Đọc ô nhập ngân sách tháng: `9tr`, `9.000.000đ`, hoặc `9` (hiểu là 9 triệu).
enum BudgetInput {
    static func parse(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if let number = Int(text), (1..<1_000).contains(number) {
            return number * 1_000_000
        }
        return AmountParser.amount(from: text)
    }
}
