import Foundation

/// Câu hỏi mẫu cho Hỏi Pennyline, chọn theo số liệu của tháng này để chắc chắn trả lời được từ bảng số liệu
/// (danh mục, tên khoản, từng ngày, còn lại, ngoài ngân sách).
enum AskSuggestions {
    /// Tối đa `limit` câu, câu hợp với dữ liệu nhất đứng trước. Không có khoản nào thì chỉ còn câu hỏi còn lại bao nhiêu.
    static func make(snapshot: SpendingSnapshot, categoryTitle: (String) -> String, limit: Int = 4) -> [String] {
        var questions: [String] = []
        let topCategory = snapshot.byCategory.first.map { categoryTitle($0.key) }
        if let topCategory {
            questions.append(String(localized: "Tháng này \(topCategory) hết bao nhiêu?"))
        }
        // Tên khoản hay gặp nhất, bỏ tên trùng với danh mục vừa hỏi.
        let name = snapshot.byName.first { group in
            topCategory.map { TextNormalizer.keyword($0) != TextNormalizer.keyword(group.label) } ?? true
        }
        if let name, name.count > 1 {
            let question = String(localized: "\(name.label) tháng này mấy lần?")
            questions.append(question.prefix(1).uppercased() + question.dropFirst())
        }
        if snapshot.byDay.count >= 2 {
            questions.append(String(localized: "Ngày nào tiêu nhiều nhất?"))
        }
        if snapshot.monthlyBudget > 0 {
            questions.append(String(localized: "Tháng này còn lại bao nhiêu?"))
        }
        if snapshot.byCategory.count >= 2 {
            questions.append(String(localized: "Danh mục nào tiêu nhiều nhất?"))
        }
        if snapshot.outsideBudgetTotal > 0 {
            questions.append(String(localized: "Các khoản ngoài ngân sách là bao nhiêu?"))
        }
        return Array(questions.prefix(limit))
    }
}
