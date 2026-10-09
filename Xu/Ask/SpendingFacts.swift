import Foundation

/// Bảng số liệu dạng chữ đưa cho mô hình, và phép kiểm tra câu trả lời.
/// Mọi con số đã được app tính và định dạng sẵn; mô hình chỉ được chép lại.
enum SpendingFacts {
    static let maxNames = 25

    static func sheet(_ snapshot: SpendingSnapshot, calendar: Calendar, categoryTitle: (String) -> String) -> String {
        var lines = [
            "Ngân sách tháng: \(MoneyFormatter.short(snapshot.monthlyBudget))",
            "Đã tiêu tháng này: \(MoneyFormatter.short(snapshot.spent))",
            snapshot.remaining >= 0
                ? "Còn lại tháng này: \(MoneyFormatter.short(snapshot.remaining))"
                : "Đã vượt ngân sách tháng: \(MoneyFormatter.short(-snapshot.remaining))",
        ]
        if snapshot.outsideBudgetTotal > 0 {
            lines.append("Các khoản ngoài ngân sách: \(MoneyFormatter.short(snapshot.outsideBudgetTotal))")
        }
        if !snapshot.byCategory.isEmpty {
            lines.append("Theo danh mục:")
            lines += snapshot.byCategory.map { "- \(categoryTitle($0.key)): \(describe($0))" }
        }
        if !snapshot.byName.isEmpty {
            lines.append("Theo tên khoản:")
            lines += snapshot.byName.prefix(maxNames).map { "- \($0.label): \(describe($0))" }
        }
        if !snapshot.byDay.isEmpty {
            lines.append("Theo ngày:")
            lines += snapshot.byDay.map { day in
                let parts = calendar.dateComponents([.day, .month], from: day.day)
                return "- ngày \(parts.day ?? 0)/\(parts.month ?? 0): \(MoneyFormatter.short(day.total))"
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "232k cho 8 lần, trung bình 29k mỗi lần"
    static func describe(_ group: SpendingSnapshot.Group) -> String {
        let total = "\(MoneyFormatter.short(group.total)) cho \(group.count) lần"
        return group.count > 1 ? "\(total), trung bình \(MoneyFormatter.short(group.average)) mỗi lần" : total
    }

    /// Mọi con số trong câu trả lời đều phải có sẵn trong bảng số liệu hoặc trong câu hỏi.
    static func usesOnlyKnownNumbers(_ answer: String, sheet: String, question: String) -> Bool {
        let known = numbers(in: sheet).union(numbers(in: question))
        return numbers(in: answer).isSubset(of: known)
    }

    static func numbers(in text: String) -> Set<String> {
        let text = TextNormalizer.lowercased(text)
        // Con số đi liền đơn vị ("232k", "8 lần"), để "9 lần" không lọt qua nhờ "9tr".
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*(?:\s?(?:k|tr|lần|đ|%)(?![\p{L}]))?"#) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } })
    }
}
