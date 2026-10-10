import Foundation

/// Tiến độ của một mục tiêu tiết kiệm.
struct SavingsProgress: Equatable, Sendable {
    var target: Int
    var saved: Int
    /// Từ 0 đến 1.
    var fraction: Double
    /// Còn thiếu bao nhiêu; 0 khi đã đủ.
    var remaining: Int
    var isDone: Bool
    /// Đã quá hạn mà chưa đủ tiền.
    var isOverdue: Bool
    /// Số tháng còn lại tới hạn, tính cả tháng dở; nil khi không đặt hạn hoặc đã quá hạn.
    var monthsLeft: Int?
    /// Mỗi tháng cần để dành bao nhiêu (làm tròn lên nghìn) để kịp hạn; nil khi không có hạn, đã đủ hoặc quá hạn.
    var neededPerMonth: Int?
}

enum SavingsPlanner {
    static let maxNameLength = 40

    static func progress(target: Int, saved: Int, deadline: Date?, now: Date, calendar: Calendar) -> SavingsProgress {
        let saved = max(0, saved)
        let remaining = max(0, target - saved)
        let isDone = target > 0 && saved >= target
        let months = deadline.flatMap { monthsLeft(until: $0, now: now, calendar: calendar) }
        let isOverdue = !isDone && deadline.map { calendar.startOfDay(for: $0) < calendar.startOfDay(for: now) } == true
        let needed: Int? = if let months, !isDone { ceilToThousand((remaining + months - 1) / months) } else { nil }
        return SavingsProgress(
            target: target,
            saved: saved,
            fraction: target > 0 ? min(1, Double(saved) / Double(target)) : 0,
            remaining: remaining,
            isDone: isDone,
            isOverdue: isOverdue,
            monthsLeft: months,
            neededPerMonth: needed
        )
    }

    /// Số tháng tới hạn, tháng dở tính là một tháng, ít nhất một. Nil khi hạn đã qua.
    static func monthsLeft(until deadline: Date, now: Date, calendar: Calendar) -> Int? {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: deadline)
        guard to >= from else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: from, to: to)
        return max(1, (parts.month ?? 0) + ((parts.day ?? 0) > 0 ? 1 : 0))
    }

    static func ceilToThousand(_ amount: Int) -> Int {
        (amount + 999) / 1_000 * 1_000
    }

    /// Tên mục tiêu đã làm gọn; nil khi trống.
    static func cleanName(_ name: String) -> String? {
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxNameLength))
    }
}
