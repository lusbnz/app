import Foundation

/// Một khoản chi nhìn từ phía tổng hợp số liệu.
struct SpendingRecord: Equatable, Sendable {
    var name: String
    var amount: Int
    var categoryKey: String
    var date: Date
    var isOutsideBudget: Bool = false
}

/// Số liệu của tháng đã tổng hợp sẵn. Màn hình Tháng và Hỏi Xu đều đọc từ đây, không đọc dữ liệu thô.
struct SpendingSnapshot: Equatable, Sendable {
    struct Group: Equatable, Sendable, Identifiable {
        /// Khóa danh mục, hoặc tên khoản đã chuẩn hóa.
        var key: String
        /// Tên như người dùng gõ lần gần nhất; với danh mục thì trùng `key`.
        var label: String
        var total: Int
        var count: Int

        var id: String { key }
        var average: Int { count > 0 ? total / count : 0 }
    }

    struct Day: Equatable, Sendable {
        var day: Date
        var total: Int
    }

    var monthlyBudget: Int
    /// Chi trong ngân sách từ đầu tháng.
    var spent: Int
    var remaining: Int
    var outsideBudgetTotal: Int
    /// Giảm dần theo tổng, chỉ gồm khoản trong ngân sách.
    var byCategory: [Group]
    /// Giảm dần theo tổng, gồm mọi khoản.
    var byName: [Group]
    /// Tăng dần theo ngày, chỉ gồm khoản trong ngân sách.
    var byDay: [Day]

    static func make(records: [SpendingRecord], monthlyBudget: Int, now: Date, calendar: Calendar) -> SpendingSnapshot {
        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        let records = records
            .filter { $0.date >= month.start && $0.date < month.end }
            .sorted { $0.date < $1.date }
        let inBudget = records.filter { !$0.isOutsideBudget }
        let spent = inBudget.reduce(0) { $0 + $1.amount }

        var days: [Date: Int] = [:]
        for record in inBudget {
            days[calendar.startOfDay(for: record.date), default: 0] += record.amount
        }
        return SpendingSnapshot(
            monthlyBudget: monthlyBudget,
            spent: spent,
            remaining: monthlyBudget - spent,
            outsideBudgetTotal: records.filter(\.isOutsideBudget).reduce(0) { $0 + $1.amount },
            byCategory: groups(inBudget) { ($0.categoryKey, $0.categoryKey) },
            byName: groups(records) { (TextNormalizer.keyword($0.name), $0.name) },
            byDay: days.map { Day(day: $0.key, total: $0.value) }.sorted { $0.day < $1.day }
        )
    }

    private static func groups(_ records: [SpendingRecord], key: (SpendingRecord) -> (key: String, label: String)) -> [Group] {
        var table: [String: Group] = [:]
        for record in records {
            let (key, label) = key(record)
            guard !key.isEmpty else { continue }
            var group = table[key] ?? Group(key: key, label: label, total: 0, count: 0)
            group.label = label
            group.total += record.amount
            group.count += 1
            table[key] = group
        }
        return table.values.sorted { ($0.total, $1.key) > ($1.total, $0.key) }
    }
}
