import Foundation

/// Một khoản có vẻ là đăng ký: cùng tên, số tiền gần như cố định, lặp đều theo tuần, tháng hoặc năm (Netflix, gửi xe tuần, tên miền).
struct DetectedSubscription: Equatable, Sendable, Identifiable {
    enum Cadence: String, Sendable {
        case weekly, monthly, yearly
    }

    /// Tên đã chuẩn hóa (`TextNormalizer.keyword`).
    var key: String
    /// Tên như người dùng gõ lần gần nhất.
    var name: String
    var categoryKey: String
    var isOutsideBudget: Bool
    var cadence: Cadence
    /// Số tiền lần gần nhất.
    var amount: Int
    /// Số tiền lần ngay trước đó khi lần gần nhất khác nó; nil khi số tiền không đổi. Dương `amount - previousAmount` là tăng giá.
    var previousAmount: Int?
    var occurrences: Int
    var firstDate: Date
    var lastDate: Date
    /// Dự kiến lần tới.
    var nextDate: Date
    /// Gợi ý để tạo khoản định kỳ: ngày trong tháng, thứ (theo `Calendar.weekday`) và tháng của lần gần nhất.
    var dayOfMonth: Int
    var weekday: Int
    var monthOfYear: Int

    var id: String { key }

    /// Mức đổi giá của lần gần nhất; dương là tăng.
    var priceChange: Int? { previousAmount.map { amount - $0 } }

    /// Quy ra mỗi tháng.
    var monthlyCost: Int {
        switch cadence {
        case .weekly: amount * 52 / 12
        case .monthly: amount
        case .yearly: amount / 12
        }
    }
}

/// Nhận ra khoản đăng ký từ lịch sử chi tiêu. Thận trọng: thà bỏ sót còn hơn nhận nhầm khoản ăn uống hàng ngày hay hóa đơn đổi theo tháng.
enum SubscriptionDetector {
    private struct Band {
        var cadence: DetectedSubscription.Cadence
        /// Số ngày giữa hai lần liên tiếp.
        var days: ClosedRange<Int>
        /// Cho phép một lần bỏ lỡ (khoảng cách gấp đôi). Nil nghĩa là không cho.
        var skip: ClosedRange<Int>?
        var minOccurrences: Int
        /// Quá chừng này ngày kể từ lần gần nhất thì coi như đã hủy.
        var staleAfter: Int
    }

    private static let bands = [
        Band(cadence: .monthly, days: 26...35, skip: 55...70, minOccurrences: 3, staleAfter: 75),
        Band(cadence: .weekly, days: 6...8, skip: 13...16, minOccurrences: 4, staleAfter: 21),
        Band(cadence: .yearly, days: 350...380, skip: nil, minOccurrences: 2, staleAfter: 430),
    ]

    /// Các khoản đăng ký đang chạy, đắt nhất (quy ra tháng) đứng trước.
    static func detect(records: [SpendingRecord], now: Date, calendar: Calendar) -> [DetectedSubscription] {
        var groups: [String: [SpendingRecord]] = [:]
        for record in records where record.amount > 0 {
            let key = TextNormalizer.keyword(record.name)
            if !key.isEmpty { groups[key, default: []].append(record) }
        }
        return groups
            .compactMap { detect(key: $0.key, group: $0.value, now: now, calendar: calendar) }
            .sorted { ($0.monthlyCost, $1.key) > ($1.monthlyCost, $0.key) }
    }

    /// Lần ghi mới có làm một khoản đăng ký đang chạy tăng giá không. `history` là các khoản đã có, chưa gồm lần ghi mới.
    static func priceIncrease(
        name: String, amount: Int, date: Date, history: [SpendingRecord], calendar: Calendar
    ) -> (name: String, from: Int, to: Int)? {
        let key = TextNormalizer.keyword(name)
        guard !key.isEmpty else { return nil }
        let same = history.filter { TextNormalizer.keyword($0.name) == key }
        let added = SpendingRecord(name: name, amount: amount, categoryKey: "other", date: date)
        guard let found = detect(key: key, group: same + [added], now: date, calendar: calendar),
              calendar.isDate(found.lastDate, inSameDayAs: date),
              let previous = found.previousAmount, found.amount > previous else { return nil }
        return (found.name, previous, found.amount)
    }

    /// Đã có khoản định kỳ nào trùng tên (khớp cả cụm, không phân biệt dấu) chưa.
    static func isTracked(_ subscription: DetectedSubscription, by recurringNames: [String]) -> Bool {
        recurringNames.contains { name in
            let key = TextNormalizer.keyword(name)
            return !key.isEmpty && (key == subscription.key
                || CategoryClassifier.ruleMatches(keyword: key, name: subscription.name)
                || CategoryClassifier.ruleMatches(keyword: subscription.key, name: name))
        }
    }

    // MARK: - Một nhóm cùng tên

    private static func detect(key: String, group: [SpendingRecord], now: Date, calendar: Calendar) -> DetectedSubscription? {
        // Mỗi ngày một lần (lấy lần ghi cuối của ngày), cũ đến mới.
        var perDay: [Date: SpendingRecord] = [:]
        for record in group.sorted(by: { $0.date < $1.date }) {
            perDay[calendar.startOfDay(for: record.date)] = record
        }
        let days = perDay.keys.sorted()
        let records = days.compactMap { perDay[$0] }
        guard records.count >= 2, let first = records.first, let last = records.last else { return nil }

        let intervals = zip(days, days.dropFirst()).map {
            calendar.dateComponents([.day], from: $0, to: $1).day ?? 0
        }
        guard let band = bands.first(where: { matches($0, count: records.count, intervals: intervals) }),
              isStable(records.map(\.amount)) else { return nil }

        let sinceLast = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.date), to: calendar.startOfDay(for: now)).day ?? 0
        guard sinceLast <= band.staleAfter else { return nil }

        let component: Calendar.Component = switch band.cadence {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        let beforeLast = records.dropLast().last
        let parts = calendar.dateComponents([.day, .month, .weekday], from: last.date)
        return DetectedSubscription(
            key: key, name: last.name, categoryKey: last.categoryKey, isOutsideBudget: last.isOutsideBudget,
            cadence: band.cadence, amount: last.amount,
            previousAmount: beforeLast.flatMap { $0.amount != last.amount ? $0.amount : nil },
            occurrences: records.count, firstDate: first.date, lastDate: last.date,
            nextDate: calendar.date(byAdding: component, value: 1, to: last.date) ?? last.date,
            dayOfMonth: parts.day ?? 1, weekday: parts.weekday ?? 2, monthOfYear: parts.month ?? 1
        )
    }

    /// Mọi khoảng cách nằm trong dải của chu kỳ, trừ nhiều nhất một lần bỏ lỡ (khoảng cách gấp đôi).
    private static func matches(_ band: Band, count: Int, intervals: [Int]) -> Bool {
        guard count >= band.minOccurrences else { return false }
        let skipped = intervals.filter { !band.days.contains($0) }
        guard intervals.count - skipped.count >= 1 else { return false }
        guard let skip = band.skip else { return skipped.isEmpty }
        return skipped.count <= 1 && skipped.allSatisfy { skip.contains($0) }
    }

    /// Số tiền gần như cố định: nhiều nhất ba mức khác nhau (có thể có tăng giá) và mức cao nhất không quá 1,6 lần mức thấp nhất.
    private static func isStable(_ amounts: [Int]) -> Bool {
        guard let low = amounts.min(), let high = amounts.max(), low > 0 else { return false }
        return Set(amounts).count <= 3 && high * 10 <= low * 16
    }
}
