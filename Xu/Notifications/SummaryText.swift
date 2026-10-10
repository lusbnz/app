import Foundation

/// Chữ của thông báo tổng kết, ghép từ số liệu của `PeriodSummary`.
enum SummaryText {
    struct Content: Equatable {
        var title: String
        var body: String
    }

    /// `categoryTitle` đổi khóa danh mục thành tên hiện cho người dùng (danh mục tự thêm cũng có tên).
    static func compose(_ summary: PeriodSummary, categoryTitle: (String) -> String, calendar: Calendar) -> Content {
        let spent = MoneyFormatter.short(summary.spent)
        var sentences: [String] = []
        let title: String
        switch summary.kind {
        case .week:
            title = String(localized: "Tổng kết tuần")
            sentences.append(String(localized: "Tuần này bạn đã tiêu \(spent)."))
            if let delta = summary.delta {
                let amount = MoneyFormatter.short(abs(delta))
                sentences.append(delta > 0 ? String(localized: "Tăng \(amount) so với tuần trước.")
                    : delta < 0 ? String(localized: "Giảm \(amount) so với tuần trước.")
                    : String(localized: "Bằng tuần trước."))
            }
        case .month:
            title = String(localized: "Tổng kết \(VietnameseDate.monthTitle(summary.interval.start, calendar: calendar))")
            if let budget = summary.budget, let leftover = summary.leftover {
                let total = MoneyFormatter.short(budget)
                let amount = MoneyFormatter.short(abs(leftover))
                sentences.append(leftover >= 0 ? String(localized: "Đã tiêu \(spent) trên \(total), còn dư \(amount).")
                    : String(localized: "Đã tiêu \(spent) trên \(total), vượt \(amount)."))
            } else {
                sentences.append(String(localized: "Tháng này bạn đã tiêu \(spent)."))
            }
            if let delta = summary.delta {
                let amount = MoneyFormatter.short(abs(delta))
                sentences.append(delta > 0 ? String(localized: "Tăng \(amount) so với tháng trước.")
                    : delta < 0 ? String(localized: "Giảm \(amount) so với tháng trước.")
                    : String(localized: "Bằng tháng trước."))
            }
        }
        if let key = summary.topCategoryKey, summary.topCategoryAmount > 0 {
            sentences.append(String(localized: "Nhiều nhất: \(categoryTitle(key)) \(MoneyFormatter.short(summary.topCategoryAmount))."))
        }
        return Content(title: title, body: sentences.joined(separator: " "))
    }
}
