import Foundation

/// Chữ mô tả một tuần, dùng ở tiêu đề tuần (màn Hôm nay) và ở màn Chi tiết tuần.
enum WeekText {
    /// Tuần này so với đúng các ngày đó của tuần trước; tuần đã qua so với cả tuần trước nó. Nil khi chưa có gì để so.
    static func comparison(_ summary: WeekSummary) -> String? {
        guard summary.hasPrevious else { return nil }
        let amount = MoneyFormatter.short(abs(summary.delta))
        switch (summary.isCurrent, summary.delta) {
        case (_, 0): return summary.isCurrent ? String(localized: "bằng cùng ngày tuần trước") : String(localized: "bằng tuần trước")
        case (true, 1...): return String(localized: "tăng \(amount) so với cùng ngày tuần trước")
        case (true, _): return String(localized: "giảm \(amount) so với cùng ngày tuần trước")
        case (false, 1...): return String(localized: "tăng \(amount) so với tuần trước")
        case (false, _): return String(localized: "giảm \(amount) so với tuần trước")
        }
    }
}
