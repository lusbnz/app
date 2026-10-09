import Foundation

/// Một khoản đã ghi, đủ để so với khoản sắp ghi.
struct RecentEntry: Equatable, Sendable {
    var name: String
    var amount: Int
    /// Ngày phát sinh.
    var date: Date
    /// Lúc bấm Ghi.
    var createdAt: Date
}

/// Phát hiện khoản vừa ghi lại một lần nữa (bấm đúp, gợi ý chạm hai lần, nói hai lần).
enum DuplicateDetector {
    /// Trong vòng bấy nhiêu giây kể từ lần ghi trước thì coi là có thể trùng.
    static let window: TimeInterval = 5 * 60

    /// Khoản vừa ghi giống hệt (cùng tên, cùng số tiền, cùng ngày phát sinh) trong `window`; nhiều khoản thì lấy khoản mới nhất.
    static func match(
        name: String, amount: Int, date: Date, among recent: [RecentEntry], now: Date, calendar: Calendar
    ) -> RecentEntry? {
        let key = TextNormalizer.keyword(name)
        return recent
            .filter {
                let age = now.timeIntervalSince($0.createdAt)
                return $0.amount == amount && TextNormalizer.keyword($0.name) == key
                    && age >= 0 && age <= window && calendar.isDate($0.date, inSameDayAs: date)
            }
            .max { $0.createdAt < $1.createdAt }
    }
}
